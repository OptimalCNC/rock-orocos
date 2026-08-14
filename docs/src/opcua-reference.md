# Native OPC UA Reference

This chapter defines the native OPC UA behavior currently exported by the
installed Orocos/Rock toolchain. Planned security changes are listed
separately under Planned Work.

> [!IMPORTANT]
> The current endpoint is loopback-only. Non-loopback listening remains
> rejected until the planned PKI and authorization contract is implemented.

## Commands And Endpoint

- `deployer-opcua` selects the executable for `OROCOS_TARGET`.
- `ctaskbrowser-opcua URL COMPONENT` connects to a published component.
- The default URL is `opc.tcp://127.0.0.1:4840/rtt`.
- `--opcua-port` and `--opcua-endpoint-path` select a different local endpoint.

## Startup And Datatype Registry

Import every required typekit and OPC UA transport plugin before the first
`opcua.start()` attempt. The first start attempt freezes the process-wide
datatype registry. `opcua.endpointUrl()` reports configuration while stopped;
`opcua.isRunning()` becomes true only after listener startup and complete
Deployer publication.

Starting an already running endpoint is a successful no-op. A failed startup
does not expose a partially published Deployer.

## Static Component Publication

`opcua.publishComponent(name)` validates and publishes the complete supported
RTT interface as one transaction. Publishing the same component instance again
is a successful no-op. `Server=true` does not publish a component.

Publication is static: resources added after publication are not added to the
endpoint. There is no public unpublish or replacement operation, and the
Deployer rejects unloading a published component while the endpoint exists.

## RTT Interface Mapping

The object model recursively maps root and nested services. Non-empty
`Operations`, `Properties`, `Attributes`, `Ports`, and `Services` categories
are published; empty category objects are omitted. Empty RTT services remain
visible so their identity and documentation are preserved.

- operations become OPC UA Methods;
- properties become readable and, when supported by RTT, writable Variables;
- attributes become Variables with RTT mutability preserved;
- constants are read-only Variables;
- ports become metadata Objects with one direction-specific sample Variable;
- nested services use the same recursive mapping; and
- generated RTT port services remain available below their owning service.

## Port Contract

Each supported port has an Object below `Ports/<name>`. Its `type` and
`description` children are read-only String Variables. Its read-only
`direction` child is a scalar `Int32`: input is `0` and output is `1`.

The canonical sample surface is a child Variable named `value`. Its OPC UA
datatype and value rank exactly match the registered RTT type protocol:

| RTT port | `value` access | Behavior |
|---|---|---|
| Input | `CurrentRead \| CurrentWrite` | Each valid OPC UA Write attempts one delivery to the RTT input port. |
| Retaining output | `CurrentRead` only | Read or monitor the latest retained RTT sample without consuming it. |
| Non-retaining output | absent | No canonical sample Variable is published. |

Input `value` reads return the last OPC UA sample successfully delivered to the
RTT input port. Before the first successful delivery, Read and monitoring
return `BadWaitingForInitialData`. Every valid Write still attempts one RTT
delivery, including an equal value; failed Writes do not replace the readback.
A type or rank mismatch returns `BadTypeMismatch`. A successful Write means
that the bridge accepted delivery to the RTT port. The readback is bridge-owned
command state, not component consumption, acknowledgement, or process state,
and does not mean that component logic consumed, processed, or acted on the
sample.

Retaining output `value` returns `BadWaitingForInitialData` until the first
sample exists. Later reads are non-consuming and return the current retained
sample. This is a latest-state contract: intermediate samples may be coalesced
or missed. It does not project RTT connection policy, FIFO depth, buffering,
locking, transport, or other QoS into OPC UA.

There are no canonical `Ports/<name>/read` or `Ports/<name>/write` Methods.
The ordinary RTT-generated port service remains recursively mapped below
`Services/<name>`, including operations such as `read`, `clear`, `write`, or
`last` when RTT provides them. Those operations belong to the service mapping;
they are not the canonical OPC UA dataport transfer surface.

## Task State Contract

Every ordinary `TaskContext` provides the root operations `getTaskState()` and
`getTargetState()`. They are read-only `ClientThread` operations: the first
reports the state currently occupied, while the second reports the transition
destination. Their values can differ while a lifecycle transition is in
progress.

Both operations are published through the ordinary operation mapper as OPC UA
Methods. Their RTT result type remains `TaskState`, represented on the wire by
one scalar built-in `Int32`:

| Code | RTT state |
|---:|---|
| `0` | `Init` |
| `1` | `PreOperational` |
| `2` | `FatalError` |
| `3` | `Exception` |
| `4` | `Stopped` |
| `5` | `Running` |
| `6` | `RunTimeError` |

Other scalar types, arrays, and codes outside `0..6` are schema errors. The
component object has no synthetic `lifecycleState` child.

## Custom Datatypes

RTT typekits own C++ structure and sequence metadata. OPC UA transport plugins
register provider-owned namespace URIs, NodeIds, dependency information, and
codecs before endpoint startup. Identical registrations are idempotent;
conflicting, cyclic, missing-dependency, and late registrations fail with
deterministic diagnostics.

Canonical sequence names include `Float64Array`, `Int32Array`, `StringArray`,
and `RtString`. Remote endpoints cannot trigger local plugin loading.

## Proxy And TaskBrowser

`TaskContextProxy` reconstructs the supported RTT service graph, resource
mutability, operations, and ports from the endpoint. It validates each port's
`direction`, `value` datatype, value rank, and access before creating a local
mirror. Proxy inputs write the remote Variable. Proxy outputs poll its latest
value at `port_poll_interval`; they do not reconstruct server-side sample
history or `FlowStatus`. Polling may publish an unchanged retained value again,
so local `NewData` identifies a proxy update, not necessarily a distinct remote
RTT write. Outputs without `value` are not mirrored as ports, while their
generated services remain available.

The proxy invokes the native `getTaskState` and `getTargetState` Methods
independently and validates their exact `TaskState` result schema. Its
lifecycle predicates invoke the matching
native Boolean operations rather than inferring results from enum ordering.
An unavailable Method, incompatible result, or invalid state code marks the
remote interface stale.

The installed TaskBrowser can inspect and edit supported scalar and structured
values, invoke mapped operations, and reconnect without depending on the
server's source tree.

## Failure And Lifetime Rules

One unsupported resource rejects the whole component publication. Diagnostics
remain available through `opcua.unsupportedResources(name)`. Failed
publication leaves no partial component subtree.

Published callbacks retain the component and operation storage they use. A
non-returning OwnThread operation can delay endpoint shutdown; its storage is
never released early.

## Verification

Run the maintained package and installed-prefix checks described in
[Package Test Results](./package-test-results.md). The public contract is the
observable installed behavior, not temporary probe output or a historical
feature-plan transcript.
