# OPC UA Static Publication Lifecycle Design

Date: 2026-08-05

Status: Implemented and verified for the generic toolchain on 2026-08-05

## Purpose

Define a deliberately small startup, publication, datatype, and component
lifetime contract for `deployer-opcua`, `OpcUaDeploymentComponent`, and
`rtt_opcua`.

This version treats the OPC UA address-space topology as static. It supports
explicit whole-component publication after endpoint startup, but it does not
support unpublication, replacement, or reconciliation. Those operations need
their own requirements and lifecycle design before they are implemented.

## Scope And Dependency Boundary

This is generic Orocos/Rock toolchain work in RTT, `rtt_opcua`, and OCL. It
must not depend on MetaNC or contain application-specific types.

The dependency baseline is:

- open62541 `v1.4.15`
- open62541pp `v0.21.2`

Both dependencies are consumed without local source modifications. Their unit
tests are not configured or compiled as part of this work. Maintained
`rtt_opcua` and OCL integration tests verify the dependency behavior that this
toolchain relies on.

CORBA sources remain available, but this workspace builds with CORBA disabled.

## User Model

`deployer-opcua` owns one local `OpcUaDeploymentComponent`. That object is the
ordinary OCL Deployer and the owner of the embedded OPC UA server. It does not
create a second Deployer object.

The executable initially provides:

- a local Deployer;
- its local `opcua` service;
- an embedded local TaskBrowser when running interactively; and
- a configured but stopped OPC UA endpoint.

The local TaskBrowser can import packages and load components before OPC UA
starts. `ctaskbrowser-opcua` is a separate client and cannot connect until
`opcua.start()` succeeds.

The normal flow is:

```text
import("sample_typekit")
loadComponent("sample", "SampleComponent")
opcua.start()
opcua.publishComponent("sample")
```

The import must load the RTT typekit and its OPC UA transport plugin before
`start()`. Components may be loaded later, but every datatype and codec that
they need must already have been registered before endpoint startup.

## Endpoint Lifecycle

The deployment service has these internal states:

```text
Created --start()--> Starting --success--> Running
                         |
                         +--failure--> StartFailed

StartFailed --start()--> Starting
Running --start()-------> Running

Created / StartFailed / Running --destructor--> Stopping --> Destroyed
```

There is no public stop, reconfigure, or restart cycle. Teardown belongs to
process or component destruction.

The public observations are:

- `isRunning()` is true only after the endpoint is running and the complete
  Deployer model has been published.
- `endpointUrl()` returns the configured connection URL, such as
  `opc.tcp://127.0.0.1:4840/rtt`. It is available before startup and does not
  by itself mean that the endpoint is listening.
- `lastError()` returns the most recent failed deployment-service command.
- A successful command clears `lastError()`.

Lifecycle and publication commands are serialized. A caller cannot observe or
mutate a half-built endpoint or component publication.

## Datatype Registry Lifetime

The process-wide datatype-provider registry is mutable only before the first
`start()` attempt.

The first attempt registers canonical RTT protocols and freezes the registry
for the remaining process lifetime. The registry remains frozen if endpoint
startup or Deployer publication later fails. A failed start may be retried
with the same registry and server configuration, but adding a missing provider
requires a new process.

This contract matches the selected dependency baseline: custom datatype arrays
are assembled as part of endpoint configuration and are not mutated while the
server runs.

Late provider or protocol registration fails with a diagnostic that identifies
the provider or RTT type and states that the process must be restarted.

## Public Deployment Service

The `opcua` service exposes this lifecycle API:

```text
bool start()
bool isRunning()
String endpointUrl()
String lastError()
bool publishComponent(String component)
StringArray unsupportedResources(String component)
```

There is no `unpublishComponent()` operation in this version.

Existing client/proxy functionality remains available, but it is independent
of the server publication lifecycle. This design adds no live graph refresh or
replacement behavior.

Before `start()` succeeds, `publishComponent()` returns false with an
"OPC UA server is not running" diagnostic. It does not queue the request.

## Startup Transaction

`start()` performs one synchronous transaction:

1. Register canonical generic RTT protocols, including `RTT::ConnPolicy`.
2. Freeze and validate datatype providers and type protocols.
3. Start the loopback OPC UA endpoint.
4. Construct the static RTT object model.
5. Strictly validate and publish the Deployer.
6. Mark the deployment service running.

Startup publishes only the Deployer. It does not publish site-file components,
loaded peers, components marked `Server=true`, or remote proxies.

Startup succeeds only when the complete Deployer interface is present. On
failure, the candidate Deployer model is discarded, the listener is stopped,
`isRunning()` remains false, and `lastError()` identifies the failed step. The
datatype registry is not reopened.

Repeated `start()` calls while running are successful no-ops. They do not
recreate the endpoint or republish nodes.

## Explicit Static Publication

`publishComponent(name)` resolves `name` to the Deployer itself or a known
local peer. It rejects unknown names and remote `TaskContextProxy` instances.

Before changing the address space, `rtt_opcua` snapshots and validates the
complete supported RTT interface:

- component metadata and nested services;
- attributes, properties, and constants;
- operations and their arguments and results;
- input and output ports;
- every required RTT-to-OPC-UA codec; and
- deterministic NodeIds and datatype references.

Publication is strict. If one resource is unsupported:

- `publishComponent()` returns false;
- no component subtree is visible;
- the object-model revision does not change;
- all unsupported resources are retained for
  `unsupportedResources(component)`; and
- `lastError()` summarizes the failure.

After successful preflight, the complete component subtree is created. An
unexpected insertion failure removes only the candidate root and descendants
created by that attempt before returning failure. This is internal transaction
rollback, not public unpublication.

Callback state created by a failed attempt is closed and holds no usable raw
component access. Stock open62541pp may retain its inert callback adapter
storage until server teardown; this is an accepted dependency limitation for
this version.

A repeated publication of the same live component instance is a successful
no-op. A different instance with the same component name is rejected. There is
no in-place replacement.

Once published, the component topology is fixed for the endpoint lifetime.
Adding or removing RTT resources does not update OPC UA nodes. Runtime values,
operations, properties, attributes, and port data continue to work; "static"
refers only to address-space topology.

No reconciliation worker or public reconciliation operation runs.

## `Server=true`

`Server=true` does not cause OPC UA publication during site loading, component
loading, or endpoint startup. It remains OCL deployment metadata for existing
configuration behavior.

For OPC UA, `publishComponent(name)` is the only command that publishes a
component other than the Deployer. The component does not need a `Server=true`
entry.

## Published Component Lifetime

A published component must remain loaded until `deployer-opcua` shuts down.
This is the central safety invariant of the static model.

OCL gains a default-allow pre-unload hook. `OpcUaDeploymentComponent`
overrides it to reject unloading any component in its publication registry:

```text
Cannot unload component 'sample': it is published through OPC UA
```

The rejection happens before disconnection, activity destruction, or
`ComponentLoader` deletion. Other deployer implementations retain their
existing unload behavior. Unpublished components may be unloaded normally.

This guard covers unloads performed through the owning Deployer. Directly
bypassing the Deployer and deleting a published component is unsupported.

OPC UA callbacks use weak publication state and acquire a component lease
before accessing RTT. An OwnThread operation that exceeds its OPC UA request
timeout retains its lease, arguments, result storage, and send handle until the
RTT operation actually completes.

Shutdown proceeds in this order:

1. Reject new server activity and callback lease acquisition.
2. Stop the endpoint and port bridges.
3. Wait for retained operations and callbacks to release their leases.
4. Release the object model and component publications.
5. Allow ordinary OCL component destruction.

An RTT operation that never returns can delay process shutdown. That is an
explicit limitation of this version and is safer than releasing live callback
state or component storage early.

Unpublication and unload-after-publication are deferred. A future design may
add them and then relax the unload guard.

## Generic `ConnPolicy` Mapping

The complete Deployer interface contains `connect`, `stream`, and
`createStream` operations that accept `RTT::ConnPolicy`. `rtt_opcua` therefore
owns a generic OPC UA structure and codec for this RTT-owned type.

Provider identity:

```text
provider: rtt-foundation
namespace URI: urn:orocos:rtt
datatype NodeId: types/ConnPolicy
binary encoding NodeId: encodings/ConnPolicy/Binary
schema fingerprint: rtt-opcua/ConnPolicy/v1
```

The mapping preserves all public fields: `type`, `size`, `lock_policy`,
`init`, `pull`, `buffer_policy`, `max_threads`, `mandatory`, `transport`,
`data_size`, and `name_id`.

The codec converts through an OPC UA-owned wire value. It must not reinterpret
an RTT C++ object containing `std::string` as an open62541 structure. Server
and proxy paths use the same field mapping.

## Failure And Diagnostic Rules

Expected command failures return false and do not throw through RTT or OPC UA
callback boundaries. `lastError()` distinguishes at least:

- server not running;
- unknown local component;
- remote proxy publication attempt;
- duplicate component name with a different instance;
- published component unload attempt;
- unsupported resource and RTT type;
- datatype registry frozen;
- endpoint startup failure; and
- address-space publication or rollback failure.

`unsupportedResources(component)` reports the most recent failed strict
publication. Each message retains the component name, complete resource path,
resource kind, canonical RTT type name, and reason.

## Test Contract

Implementation begins with failing maintained-package tests that prove:

1. Construction leaves OPC UA stopped, and pre-start publication fails rather
   than queues.
2. `start()` publishes the complete Deployer only; a loaded `Server=true`
   component remains absent until explicit publication.
3. Repeated start and repeated publication are idempotent.
4. A supported component exposes its complete snapshot.
5. An unknown RTT type rejects the complete component with queryable
   diagnostics and no residual subtree.
6. An injected node-creation failure rolls back the candidate subtree.
7. RTT interface changes after publication are not reconciled.
8. A published component cannot be unloaded, while an unpublished component
   can be unloaded normally.
9. Timed-out OwnThread operations retain their lifetime through endpoint
   shutdown.
10. `RTT::ConnPolicy` round-trips every field and makes the Deployer connection
    operations visible through `TaskContextProxy`.
11. The first start freezes the registry, including after failed startup.
12. The public service contains no unpublish or reconciliation operation.

The dependency libraries' own test targets are not built. Tests link against
the unmodified selected versions and cover only the maintained RTT,
`rtt_opcua`, OCL, executable, and external-fixture surfaces.

## Verification And Manual Acceptance

All authoritative builds, installs, isolated homes, logs, caches, and runtime
fixtures use new directories below `/tmp`. Nothing is installed into, sourced
from, or resolved from `~/.orocos`.

Verification builds maintained packages with C++20 and their warning policy,
with CORBA disabled. It runs focused package tests, the complete maintained
package suites, and sanitizer coverage for `rtt_opcua` and OCL.

Manual acceptance uses the installed temporary prefix:

```text
deployer-opcua
  import("sample_typekit")
  loadComponent("sample", "SampleComponent")
  opcua.start()
  opcua.publishComponent("sample")

ctaskbrowser-opcua
  connect to opcua.endpointUrl()
  browse and call the complete Deployer interface
  browse and call the sample component
  write and read a writable attribute and property
```

An external fixture with an unregistered type must fail strict publication and
remain absent from remote browse results.

## Non-Goals

- public component unpublication
- unloading or replacing a published component
- address-space reconciliation or live graph refresh
- live datatype registration after server startup
- a public stop/reconfigure/restart API
- automatic publication based on `Server=true`
- publication modes or resource allowlists
- PKI, non-loopback listening, RBAC, or access-control policy
- modifications to open62541 or open62541pp source
- building open62541 or open62541pp unit tests
- replacing or removing CORBA source packages
- MetaNC compatibility NodeIds or application-specific types
