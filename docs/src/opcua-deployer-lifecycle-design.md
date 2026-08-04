# OPC UA Deployer Lifecycle Design

Date: 2026-08-04

Status: Discussion decisions accepted; written specification pending review

## Purpose

Define the startup, publication, datatype, and component-lifetime contract for
`deployer-opcua` and `OpcUaDeploymentComponent`.

This design amends the original custom-datatype design. The datatype provider
registry remains a pre-start registry, but server startup is now explicitly
controlled through the local Deployer API and component publication is strict
and explicit.

## Scope

This is generic Orocos/Rock toolchain work in RTT, `rtt_opcua`, and OCL. It
must not depend on MetaNC or contain application-specific types.

The selected dependency baseline remains:

- open62541 `v1.4.15`
- open62541pp `v0.21.2`

CORBA sources remain available but are not built by this workspace.

## User Model

`deployer-opcua` owns one local `OpcUaDeploymentComponent`. That object is both
the ordinary OCL Deployer and the owner of an embedded OPC UA server. It does
not create a second remote Deployer object.

The executable starts with:

- a local Deployer
- its local `opcua` service
- an embedded local TaskBrowser when running interactively
- an OPC UA server in the stopped state

The embedded TaskBrowser can call the local Deployer before OPC UA starts.
`ctaskbrowser-opcua` is a separate OPC UA client and cannot connect until
`opcua.start()` succeeds.

The normal custom-type flow is:

```text
import("sample_typekit")
loadComponent("sample", "SampleComponent")
opcua.start()
opcua.publishComponent("sample")
```

The import must load both the RTT typekit and its OPC UA transport plugin.
Loading a component after startup is allowed only when every OPC UA datatype
and codec it needs was registered before startup.

## Lifecycle State Model

The deployment service has these internal lifecycle states:

```text
Created --start()--> Starting --success--> Running
                         |
                         +--failure--> StartFailed

StartFailed --start()--> Starting
Running --start()-------> Running

Created / StartFailed / Running --destructor--> Stopping --> Destroyed
```

There is no public stop-and-reconfigure cycle in this design. Server teardown
belongs to process or component destruction.

The public observations are deliberately smaller than the internal state:

- `ready()` is true only in `Running`.
- `endpoint()` returns the configured endpoint URL before and after startup.
- `lastError()` returns the last failed deployment-service command.
- a successful command clears `lastError()`.

All lifecycle and publication transitions are serialized. A concurrent caller
either observes the completed transition or receives its result; it cannot
observe or mutate half-built deployment state.

## Datatype Registry Lifetime

The process-wide datatype-provider registry is mutable only before the first
`start()` attempt.

The first `start()` call performs canonical protocol registration and then
freezes the registry for the remaining process lifetime. This remains true if
endpoint startup or Deployer publication later fails. A failed start may be
retried with the same frozen registry and server configuration, but missing
providers cannot be added. Adding them requires a new process.

This rule matches the selected open62541/open62541pp baseline: endpoint
configuration and custom datatype arrays are assembled before the server is
run and are not mutated while it is running.

Late provider or type-protocol registration must fail with a message that
identifies the attempted provider or RTT type and states that the process must
be restarted.

## Public Deployment Service

The `opcua` service exposes these local and remote operations:

```text
bool start()
bool ready()
String endpoint()
String lastError()
bool publishComponent(String component)
bool unpublishComponent(String component)
StringArray unsupportedResources(String component)
```

Existing remote-peer management operations remain independent:

```text
bool connectRemote(String endpoint, String component, String peer)
bool disconnectRemote(String peer)
bool synchronizeRemote(String peer)
```

`publishPeer` and `unpublishPeer` are replaced by the component terminology.
No compatibility aliases are required.

Before `start()` succeeds, `publishComponent()` fails with a clear
"OPC UA server is not running" diagnostic. It does not queue publication.
This keeps the deployment order explicit and prevents a pre-start request from
silently changing what `start()` publishes.

## Startup Transaction

`start()` performs one synchronous transaction:

1. Register the canonical generic RTT protocols, including `ConnPolicy`.
2. Freeze and validate datatype providers and type protocols.
3. Create the endpoint-bound datatype registry and custom datatype nodes.
4. Construct the RTT object model.
5. Strictly validate and publish the Deployer component.
6. Mark the deployment service ready.

Startup publishes only the Deployer. It does not publish site-file components,
loaded peers, components marked `Server=true`, or remote proxies.

The transition is successful only when the complete Deployer interface is
present. If any step fails, all Deployer nodes and model registrations are
discarded, the listener is stopped, `ready()` remains false, and `lastError()`
describes the failing step. The frozen datatype registry is not reopened.

Repeated `start()` calls in `Running` are idempotent and return true without
recreating the endpoint, changing the model revision, or republishing nodes.

## `Server=true`

`Server=true` no longer causes OPC UA publication during site loading,
component loading, or endpoint startup. It remains OCL deployment metadata for
other transport behavior and compatibility with existing configuration files.

For OPC UA, `publishComponent(name)` is the only command that publishes a
component other than the Deployer. It may publish any local component known to
the Deployer; the component does not need a `Server=true` entry.

## Strict Component Publication

Publication is all-or-nothing for one component revision.

Before adding nodes, `rtt_opcua` snapshots the complete RTT service tree,
including operations, properties, attributes, constants, and ports. Every
referenced RTT type must have a bound OPC UA codec. If one resource is
unsupported:

- `publishComponent()` returns false.
- no root, lifecycle, resource, or service node for that component remains.
- the object-model revision does not change.
- every unsupported resource is retained for
  `unsupportedResources(component)`.
- `lastError()` summarizes the strict publication failure.

Address-space insertion failures use the same transaction rule. Nodes created
for the candidate component are rolled back before failure is returned.

A repeated publication of the same live component instance is idempotent and
returns true without changing the model revision. A different instance with
the same component name is rejected. Remote `TaskContextProxy` peers cannot be
republished by the local server.

`unpublishComponent()` removes the complete component model. Repeating it for
a known, already-unpublished local component succeeds without changing the
revision. Unknown component names fail. The Deployer cannot unpublish itself
while the endpoint is running.

Runtime reconciliation also applies complete candidate revisions. If an
already-published component later acquires an unsupported resource or a node
update fails, the last complete published revision remains active and the new
diagnostics are reported; a partial candidate revision is never committed.

## Component Unload Safety

OCL invokes `componentUnloaded()` before it disconnects or destroys a loaded
component. `OpcUaDeploymentComponent` uses that hook to reset the component's
OPC UA registration.

Resetting a registration performs this order:

1. Prevent new OPC UA callbacks from obtaining a component lease.
2. Wait for every existing callback and retained asynchronous invocation to
   release its lease.
3. Remove the component nodes and diagnostic state.
4. Return to OCL, which may then disconnect and destroy the component.

An OwnThread operation that exceeded the OPC UA request timeout still retains
its component lease, arguments, result storage, and send handle until the RTT
operation actually completes. Consequently, unloading a non-running component
while such an operation is busy blocks safely; it must not free the component
or invocation state early.

After unload completes, a new component with the same name is a distinct
instance and may be loaded and published normally.

## Generic `ConnPolicy` Mapping

The full Deployer interface contains `connect`, `stream`, and `createStream`
operations that accept `RTT::ConnPolicy`. `rtt_opcua` therefore owns a generic
native OPC UA structure and codec for this RTT-owned type.

Provider identity:

```text
provider: rtt-foundation
namespace URI: urn:orocos:rtt
datatype NodeId: types/ConnPolicy
binary encoding NodeId: encodings/ConnPolicy/Binary
schema fingerprint: rtt-opcua/ConnPolicy/v1
```

The structure preserves all public `ConnPolicy` state:

| OPC UA field | OPC UA type | RTT field |
| --- | --- | --- |
| `type` | `Int32` | `type` |
| `size` | `Int32` | `size` |
| `lock_policy` | `Int32` | `lock_policy` |
| `init` | `Boolean` | `init` |
| `pull` | `Boolean` | `pull` |
| `buffer_policy` | `Int32` | `buffer_policy` |
| `max_threads` | `Int32` | `max_threads` |
| `mandatory` | `Boolean` | `mandatory` |
| `transport` | `Int32` | `transport` |
| `data_size` | `Int32` | `data_size` |
| `name_id` | `String` | `name_id` |

The codec converts between an OPC UA-owned wire value and `RTT::ConnPolicy`;
it must not reinterpret a C++ object containing `std::string` as an open62541
structure. Server and proxy paths both use the same field mapping. Numeric
policy values are preserved as RTT defines them rather than introducing a new
OPC UA-only policy vocabulary.

## Failure And Diagnostic Rules

Expected command failures return false and do not throw through RTT or OPC UA
callback boundaries. `lastError()` must distinguish at least:

- server not running
- unknown local component
- remote proxy publication attempt
- duplicate component name with a different instance
- unsupported resource and RTT type
- datatype registry frozen
- endpoint startup failure
- address-space publication or rollback failure

`unsupportedResources(component)` is useful for both a published component's
latest reconciliation candidate and the most recent failed strict publication.
Messages retain component name, full resource path, resource kind, canonical
RTT type name, and reason.

## Test Contract

Implementation starts with failing tests that prove:

1. Construction and `deployer-opcua` startup leave OPC UA stopped, and a
   pre-start component publication fails rather than queues.
2. `start()` publishes the complete Deployer only; a loaded `Server=true`
   component remains absent until explicitly published.
3. Repeated start, publish, and unpublish calls obey the idempotency rules and
   do not create extra model revisions.
4. An intentionally unknown RTT type rejects the complete component with no
   residual nodes and queryable diagnostics.
5. An injected node-creation failure rolls back the complete component.
6. Unloading while an operation is busy waits for completion, including an
   operation whose remote request already returned `BadTimeout`.
7. `ConnPolicy` round-trips every field and makes the Deployer's connection
   operations visible through `TaskContextProxy`.
8. The first start freezes the registry and late provider registration remains
   rejected after both successful and failed startup.

## Manual Acceptance

All installation and manual tests use a new prefix below `/tmp`; nothing is
installed into or sourced from `~/.orocos`.

The first manual acceptance session is:

```text
deployer-opcua
  import("sample_typekit")
  loadComponent("sample", "SampleComponent")
  opcua.start()
  opcua.publishComponent("sample")

ctaskbrowser-opcua
  connect to the reported loopback endpoint
  browse and call the complete Deployer interface
  browse and call the sample component
```

A second fixture component with an unregistered type must fail strict
publication and remain absent from remote browse results. The same flow runs
under AddressSanitizer, UndefinedBehaviorSanitizer, and leak detection from the
temporary prefix.

## Non-Goals

- live datatype registration after server startup
- a public stop/reconfigure/restart API
- automatic publication based on `Server=true`
- publication modes or resource allowlists
- PKI, non-loopback listening, RBAC, or access-control policy
- replacing or removing CORBA source packages
- MetaNC compatibility NodeIds or application-specific types
