# OPC UA Deployer Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `deployer-opcua` start only through the explicit local
`opcua.start()` API, publish only a complete Deployer at startup, and publish
other local components strictly and explicitly with a generic OPC UA mapping
for `RTT::ConnPolicy`.

**Architecture:** `rtt_opcua` owns the generic `ConnPolicy` datatype and codec,
strict component snapshots, transactional address-space reconciliation, and
component leases. OCL owns deployment lifecycle state, component-name
resolution, failed-publication diagnostics, and the local service API. The
executable creates a local Deployer and TaskBrowser with the endpoint stopped;
an installed external fixture proves the import, load, start, publish, and
remote browse flow without MetaNC dependencies.

**Tech Stack:** C++20, Orocos RTT/OCL, open62541 1.4.15, open62541pp 0.21.2,
CMake, Boost.Test, mdBook, AddressSanitizer, UndefinedBehaviorSanitizer, and
LeakSanitizer.

## Global Constraints

- Work only in the root, RTT, `rtt_opcua`, and OCL
  `codex/orocos-opcua-custom-datatypes` worktrees.
- Preserve unrelated worktree edits. In particular, retain OCL's existing
  direct `<stdexcept>` include in
  `deployment/OpcUaDeploymentComponent.cpp`.
- Never install into, source from, or resolve artifacts from `~/.orocos` while
  implementing or testing. Every install prefix, build directory, `HOME`, log,
  cache, and ready file must be below a new `/tmp` directory.
- Keep open62541 at `v1.4.15` and open62541pp at `v0.21.2`.
- Keep CORBA source available and configure `ENABLE_CORBA=OFF` in this
  workspace.
- Publish the full supported RTT interface. Do not add `Server=true`
  auto-publication, queued publication, allowlists, publication modes, PKI,
  non-loopback listening, RBAC, a public stop API, or live datatype
  registration.
- Replace `publishPeer` and `unpublishPeer` with `publishComponent` and
  `unpublishComponent`; do not retain compatibility aliases.
- Treat one component revision as the transaction boundary. Unsupported types
  or node creation failures must never leave a partial component model.
- Do not merge or push default branches until the final review has summarized
  all package commits, fresh verification evidence, and remaining risks for
  user approval.

---

### Task 1: Add The Generic `RTT::ConnPolicy` Protocol

**Files:**

- Create: `toolchain/tools/rtt_opcua/src/conn_policy_protocol.hpp`
- Create: `toolchain/tools/rtt_opcua/src/conn_policy_protocol.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/type_protocol.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/type_transport_plugin.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/type_protocol_test.cpp`
- Modify: `toolchain/tools/rtt_opcua/CMakeLists.txt`

**Interfaces:**

- Consumes: RTT's existing `StructTypeInfo<RTT::ConnPolicy>("ConnPolicy")`,
  `DataTypeProvider`, `TypeProtocol`, `TypeCodec`, and endpoint registry.
- Produces one canonical provider and type protocol:

```text
provider: rtt-foundation
namespace URI: urn:orocos:rtt
datatype NodeId: types/ConnPolicy
binary encoding NodeId: encodings/ConnPolicy/Binary
schema fingerprint: rtt-opcua/ConnPolicy/v1
```

- [ ] **Step 1: Write the complete round-trip test first**

Add `conn_policy_protocol_round_trips_every_public_field` to
`tests/type_protocol_test.cpp`. Initialize all eleven fields to non-default
values and compare them field-by-field:

```cpp
RTT::ConnPolicy expected;
expected.type = RTT::ConnPolicy::BUFFER;
expected.size = 17;
expected.lock_policy = RTT::ConnPolicy::LOCKED;
expected.init = true;
expected.pull = true;
expected.buffer_policy = RTT::PerInputPort;
expected.max_threads = 6;
expected.mandatory = false;
expected.transport = 42;
expected.data_size = 4096;
expected.name_id = "fixture/channel";
```

Assert that `codecForTypeName("ConnPolicy")` exists, is scalar and writable,
uses `NodeId(1, "types/ConnPolicy")`, and round-trips the value through:

- `toVariant`
- `assignVariant`
- `makeDataSource`
- a writable proxy datasource
- a read-only proxy datasource
- an `RTT::OutputPort<RTT::ConnPolicy>`

Also inspect the endpoint registry's custom datatype and assert its binary
encoding NodeId is `encodings/ConnPolicy/Binary`.

- [ ] **Step 2: Run the test and observe the missing protocol**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel \
  --target rtt_opcua_type_protocol_test
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
  -R '^rtt_opcua_type_protocol_test$'
```

Expected: the new case fails because `codecForTypeName("ConnPolicy")` returns
null or `registerCanonicalTypeProtocols()` cannot register the type.

- [ ] **Step 3: Define an OPC UA-owned wire structure**

Keep the private interface in `src/conn_policy_protocol.hpp`:

```cpp
namespace RTT::opcua {
bool registerConnPolicyProtocol(RTT::types::TypeInfo *type_info,
                                std::string *error = nullptr);
}
```

In `src/conn_policy_protocol.cpp`, define a wire value with fixed-width
integers and an OPC UA-owned string:

```cpp
struct ConnPolicyWire {
  std::int32_t type;
  std::int32_t size;
  std::int32_t lock_policy;
  bool init;
  bool pull;
  std::int32_t buffer_policy;
  std::int32_t max_threads;
  bool mandatory;
  std::int32_t transport;
  std::int32_t data_size;
  ::opcua::String name_id;
};
```

Build it with `opcua::DataTypeBuilder<ConnPolicyWire>::createStructure()` and
eleven `.addField` calls in the exact order above. Register it through a
`DataTypeProvider` named `rtt-foundation` with URI `urn:orocos:rtt`.

- [ ] **Step 4: Implement conversion without layout reinterpretation**

Implement dedicated assignable and read-only proxy datasources, a
`ConnPolicyTypeCodec`, and a `ConnPolicyTypeProtocol`, following the external
fixture transport's ownership pattern. Encode by copying all RTT fields into a
`ConnPolicyWire`; decode by copying each wire field back and converting
`name_id` through `std::string_view`. Never cast `RTT::ConnPolicy *` to
`ConnPolicyWire *` because the RTT object owns a `std::string`.

Use `rtt-opcua/ConnPolicy/v1` as both the provider schema fingerprint and the
protocol registration fingerprint.

- [ ] **Step 5: Register `ConnPolicy` through both canonical paths**

Change `registerCanonicalTypeProtocol()` so the exact RTT name `ConnPolicy`
dispatches to `registerConnPolicyProtocol()`. Change
`registerCanonicalTypeProtocols()` to register the descriptor-backed builtins
one at a time and then obtain `Types()->type("ConnPolicy")` and register it.
Avoid holding `registrationMutex()` while calling a helper that calls the
public `registerTypeProtocol()` API.

The RTT type transport plugin must consequently accept `ConnPolicy` and still
reject noncanonical names. Add `src/conn_policy_protocol.cpp` to
`orocos-rtt-opcua` in `CMakeLists.txt`.

- [ ] **Step 6: Run focused and complete `rtt_opcua` tests**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure
```

Expected: every `rtt_opcua_*` test passes with warnings-as-errors, and the
ConnPolicy case proves all eleven fields.

- [ ] **Step 7: Commit the package change**

```bash
git -C toolchain/tools/rtt_opcua add \
  CMakeLists.txt src/conn_policy_protocol.hpp src/conn_policy_protocol.cpp \
  src/type_protocol.cpp src/type_transport_plugin.cpp \
  tests/type_protocol_test.cpp
git -C toolchain/tools/rtt_opcua commit \
  -m "feat: add native OPC UA ConnPolicy mapping"
```

### Task 2: Reject Unsupported Components Before Publication

**Files:**

- Modify: `toolchain/tools/rtt_opcua/include/rtt/opcua/object_model.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`

**Interfaces:**

- Extend registration without breaking existing callers:

```cpp
std::optional<ComponentRegistration>
registerComponent(RTT::TaskContext &component, std::string *error = nullptr,
                  std::vector<UnsupportedResource> *unsupported = nullptr);
```

- `unsupportedResources(component)` must return diagnostics for both the
  latest rejected initial publication and the latest rejected reconciliation
  candidate.

- [ ] **Step 1: Convert the unsupported-resource test to strict semantics**

Rename the current
`unsupported_resources_are_queryable_deduplicated_and_recover` test to
`unsupported_resources_reject_the_complete_initial_component`. Capture the
model revision before registration, pass the output diagnostics vector, and
assert:

```text
registration has no value
componentCount() == 0
revision is unchanged
six deduplicated diagnostics are returned and queryable
the component root does not exist
no supported sibling resource from that component exists
```

Keep exact diagnostic checks for the unsupported property, attribute, input
port, output port, consuming operation, and producing operation.

- [ ] **Step 2: Run the focused test and observe partial publication**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel \
  --target rtt_opcua_object_model_test
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
  -R '^rtt_opcua_object_model_test$'
```

Expected: the old implementation returns a registration and publishes the
supported subset, so the new strict assertions fail.

- [ ] **Step 3: Snapshot before inserting component state**

In `ObjectModelImpl::registerComponent`, validate options, construct the
`ComponentState`, and call `snapshotComponent()` before adding the state to
`components`. If `snapshot.unsupported` is nonempty:

- store the sorted diagnostics by component name in a failed-publication map
- copy them to the optional output parameter
- emit each warning through the configured warning sink
- set an error beginning `strict OPC UA publication rejected component`
- return no registration without invoking node creation or changing revision

On a successful publication, clear stale failed-publication diagnostics for
that component name. Keep component-name/instance collision checks under the
registry mutex.

- [ ] **Step 4: Make diagnostic lookup independent of registration**

Have `ObjectModel::unsupportedResources(name)` consult active candidate
diagnostics first and rejected-publication diagnostics second. Remove rejected
diagnostics when the component is successfully registered or explicitly
unregistered. Do not invent a public diagnostics-clear command.

- [ ] **Step 5: Re-run the object-model suite**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel \
  --target rtt_opcua_object_model_test
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
  -R '^rtt_opcua_object_model_test$'
```

Expected: strict unsupported publication passes, existing supported components
still publish, and no registration lifetime test regresses.

- [ ] **Step 6: Commit the strict preflight**

```bash
git -C toolchain/tools/rtt_opcua add \
  include/rtt/opcua/object_model.hpp src/object_model.cpp \
  tests/object_model_test.cpp
git -C toolchain/tools/rtt_opcua commit \
  -m "fix: reject incomplete OPC UA component models"
```

### Task 3: Make Address-Space Reconciliation Transactional

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`

**Interfaces:**

- Initial publication and later reconciliation share one transactional node
  diff implementation.
- A rejected runtime candidate preserves the last complete node set and model
  revision while updating diagnostics.

- [ ] **Step 1: Add a deterministic mid-publication failure fixture**

Add a test-only input port whose codec exists but whose bridge cannot be
created:

```cpp
class FailingInputPort final : public RTT::InputPort<std::int32_t> {
public:
  using RTT::InputPort<std::int32_t>::InputPort;
  RTT::base::PortInterface *antiClone() const override { return nullptr; }
};
```

Publish a component containing ordinary supported resources followed by this
port. Assert registration fails, the component root and every already-created
child are absent, `componentCount()` is zero, and revision is unchanged. This
exercises rollback without adding a production test hook.

- [ ] **Step 2: Add a last-good runtime candidate test**

Publish a fully supported component and record its revision and a known node.
Add the existing unsupported service at runtime and trigger reconciliation.
Assert the old node set and revision remain, the unsupported candidate nodes
are absent, and diagnostics become queryable. Remove the unsupported service,
reconcile again, and assert diagnostics clear; if the supported node set did
not change, revision remains unchanged.

- [ ] **Step 3: Run the two cases and observe residual/partial changes**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel \
  --target rtt_opcua_object_model_test
toolchain/tools/rtt_opcua/build/rtt_opcua_object_model_test \
  --run_test='*rollback*'
toolchain/tools/rtt_opcua/build/rtt_opcua_object_model_test \
  --run_test='*last_good*'
```

Expected: the current incremental delete/create implementation either leaves
candidate nodes behind or commits a partial runtime candidate.

- [ ] **Step 4: Separate shared-root creation from strict node creation**

Keep `ensureRoots()` idempotent by explicitly accepting
`BadNodeIdExists` there. Make every component `NodeSpec::create` treat
`BadNodeIdExists` as a collision and failure. This ensures a foreign or stale
component NodeId cannot be silently adopted as part of a successful model.

- [ ] **Step 5: Apply and roll back one node diff inside one server invoke**

In `reconcileComponent`, compute these collections before mutating the server:

```text
old nodes to remove or replace, leaf first
candidate nodes to add or replace, parent first
old NodeSpecs needed for rollback, parent first
all candidate paths that may have been partially created, leaf first
```

Delete old changed/removed nodes, create new/changed candidate nodes, and only
then replace the stored snapshot and increment revision. On any create failure:

1. delete every affected candidate path, including the path whose creator
   returned failure
2. recreate every removed old NodeSpec parent first
3. retain the old stored snapshot and revision
4. return the original error, appending any rollback error explicitly

Because all mutations occur in one `Server::invoke`, remote clients cannot
observe the intermediate diff.

- [ ] **Step 6: Reject unsupported runtime candidates without node mutation**

When `snapshotComponent()` reports unsupported resources for an active
component, update and emit diagnostic events but skip the node diff and leave
the old snapshot/revision intact. A later supported candidate may replace the
old revision normally.

- [ ] **Step 7: Run the complete package suite**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure
```

Expected: all package tests pass. Task 8 repeats the complete maintained graph
from a fresh temporary install under ASan, UBSan, and LSan so this task does not
depend on an implicit prerequisite prefix.

- [ ] **Step 8: Commit atomic reconciliation**

```bash
git -C toolchain/tools/rtt_opcua add \
  src/object_model.cpp tests/object_model_test.cpp
git -C toolchain/tools/rtt_opcua commit \
  -m "fix: reconcile OPC UA components atomically"
```

### Task 4: Refactor The OCL Service To Explicit Lifecycle And Publication

**Files:**

- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.hpp`
- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.cpp`
- Modify: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`
- Modify: `toolchain/tools/ocl/deployment/CMakeLists.txt`

**Interfaces:**

- Public C++ methods and `opcua` operations:

```cpp
bool startOpcUa();
bool publishComponent(const std::string &component_name);
bool unpublishComponent(const std::string &component_name);
```

- Internal helpers use distinct names:

```cpp
bool publishLocalComponent(RTT::TaskContext &component);
void releaseComponent(RTT::TaskContext *component) noexcept;
```

- [ ] **Step 1: Rewrite the lifecycle tests before implementation**

Replace the queued/partial-publication test with focused cases:

```text
explicit_start_publishes_only_the_complete_deployer
server_metadata_requires_explicit_component_publication
strict_publication_failure_is_queryable_and_leaves_no_proxy
start_publish_and_unpublish_are_idempotent
remote_components_remain_owned_as_aliased_peers
```

The first case must prove construction leaves the endpoint stopped, a
pre-start publish returns false with `OPC UA server is not running`, start
creates a Deployer proxy, and no other local peer is remotely visible.

Through the Deployer proxy, assert the full connection API is present:

```text
connect
stream
createStream
```

Through its `opcua` service, assert `publishComponent` and
`unpublishComponent` exist and `publishPeer`/`unpublishPeer` do not.

- [ ] **Step 2: Split Boost cases into fresh CTest processes**

Replace the aggregate OCL `add_test` with a `foreach(case ...)` that invokes:

```cmake
add_test(
  NAME ocl_opcua_deployment_${case}
  COMMAND ocl_opcua_deployment_test --run_test=${case}
)
```

This isolates process-wide datatype freezing and makes failures attributable
to one lifecycle contract.

- [ ] **Step 3: Run the focused cases and observe old behavior**

```bash
cmake --build toolchain/tools/ocl/build --parallel \
  --target ocl_opcua_deployment_test
ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
  -R '^ocl_opcua_deployment_.*$'
```

Expected: pre-start publication queues, `Server=true` auto-publishes, unknown
types publish partially, and the old operation names remain.

- [ ] **Step 4: Remove constructor and `Server=true` publication**

Remove `Impl::pending`, constructor calls that publish the Deployer/site
components, and publication from `componentLoaded()`. The load hook should
only maintain existing OCL component/proxy bookkeeping. Construction must not
throw because the OPC UA endpoint is intentionally stopped.

Register exact service operation names `publishComponent` and
`unpublishComponent`. Remove old aliases from both C++ and the RTT service.

- [ ] **Step 5: Implement serialized startup as one transaction**

Under `Impl::mutex`, return true unchanged only when the server, model, and
Deployer registration are all ready. Otherwise:

1. call `registerCanonicalTypeProtocols()` (including `ConnPolicy`)
2. call `server.start()` (which freezes providers)
3. construct `ObjectModel`
4. strictly register only `*this`, collecting unsupported diagnostics
5. store the Deployer registration and mark ready

On steps 3-4 failure, reset the registration/model, stop the server, retain the
process-wide registry freeze, set a specific `last_error`, and return false.
`opcUaReady()` must take the same mutex and require all three ready conditions,
not only `server.isRunning()`.

Represent the accepted transitions explicitly with an internal state enum for
`Created`, `Starting`, `Running`, `StartFailed`, `Stopping`, and `Destroyed`.
Set `Starting` before work, `Running` only after the Deployer registration is
stored, and `StartFailed` after rollback. A retry from `StartFailed` uses the
same frozen registry. `endpoint()`, `ready()`, and `lastError()` take the same
mutex so no caller observes a half-built state.

- [ ] **Step 6: Implement explicit component-name publication**

Resolve `this`/the Deployer name or a local peer. Reject unknown names, a
different instance with the same name, and `TaskContextProxy` peers. Before a
successful start, fail without queuing. For a live registration of the same
pointer, return true without changing revision.

On strict failure, retain the returned diagnostics in
`Impl::publication_diagnostics`; `unsupportedResources(name)` must query that
cache even though the component is not published. Clear the cache after a
successful publication.

`unpublishComponent` must reject the Deployer, fail for unknown names, remove
one active registration, and return true unchanged for a known local component
that is already unpublished.

Every successful service command clears `lastError()`. Expected failures set a
specific error and return false without throwing across RTT or OPC UA callback
boundaries. Add endpoint-before/after-start equality and last-error clearing to
the lifecycle test.

- [ ] **Step 7: Verify idempotency with the remote revision node**

In the test, resolve `urn:orocos:rtt` in the client namespace array and read
`/rtt/model/revision`. Assert repeated start and repeated publish do not change
it; the first unpublish increments it once; repeated unpublish leaves it
unchanged.

- [ ] **Step 8: Run all OCL OPC UA tests**

```bash
cmake --build toolchain/tools/ocl/build --parallel \
  --target ocl_opcua_deployment_test deployer-opcua ctaskbrowser-opcua
ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
  -R '^(ocl_opcua_deployment_.*|ctaskbrowser_opcua_.*)$'
```

Expected: all explicit lifecycle, remote-peer, and TaskBrowser CLI cases pass.

- [ ] **Step 9: Commit the OCL lifecycle refactor**

```bash
git -C toolchain/tools/ocl add \
  deployment/OpcUaDeploymentComponent.hpp \
  deployment/OpcUaDeploymentComponent.cpp \
  deployment/tests/opcua_deployment_test.cpp deployment/CMakeLists.txt
git -C toolchain/tools/ocl commit \
  -m "feat: make OPC UA deployment lifecycle explicit"
```

### Task 5: Freeze On Failed Start And Block Unload While Busy

**Files:**

- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.cpp`
- Modify: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`
- Modify: `toolchain/tools/ocl/deployment/CMakeLists.txt`
- Modify if required by a failing lifetime test:
  `toolchain/tools/rtt_opcua/src/object_model.cpp`
- Modify if required by a failing lifetime test:
  `toolchain/tools/rtt_opcua/src/operation_dispatcher.cpp`

- [ ] **Step 1: Add successful- and failed-start freeze cases**

Add `successful_start_freezes_registry` and
`failed_start_keeps_registry_frozen` as separate CTest processes. The failed
case holds a loopback listening socket on the configured port so
`startOpcUa()` reaches registry freeze and then fails endpoint binding.

After each first start attempt, assert `dataTypeRegistryFrozen()` is true and
attempt to register a uniquely named provider. Assert rejection includes the
provider name, states registration is late/frozen, and tells the caller to
restart the process. Retry the failed start with the same frozen registry and
configuration; it may fail again, but it must not reopen registration.

- [ ] **Step 2: Add an unload-after-`BadTimeout` component fixture**

Register a `ComponentLoader` factory for a task with an `RTT::OwnThread`
operation that sets `started`, sleeps for 200 ms, sets `completed`, and returns.
Track its destructor with a third atomic flag. Configure the object-model
operation timeout to 30 ms.

Load and explicitly publish the component, call the operation with a low-level
open62541 client, and assert the response is `BadTimeout` while
`pendingOperationCount` behavior remains covered in `rtt_opcua`.

- [ ] **Step 3: Prove unload blocks on the retained lease**

Call `deployer.unloadComponent(name)` through `std::async`. Before the slow
operation finishes, assert the future is not ready and the destructor flag is
false. Then assert the operation completes, unload returns true, the component
is destroyed, and its OPC UA root is absent. Immediately load and publish a
new instance with the same name to prove the old registration was fully reset.

- [ ] **Step 4: Run the new cases under ASan/UBSan/LSan**

```bash
ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
  -R '^ocl_opcua_deployment_(successful_start_freezes_registry|failed_start_keeps_registry_frozen|unload_waits_for_timed_out_operation)$'
```

Repeat these cases in the temporary sanitizer build created by the installed
verification task. Expected: no use-after-free, leak, deadlock, or teardown
crash.

- [ ] **Step 5: Change production lifetime code only if the red test proves it**

The existing `ComponentRegistration::reset()` and retained pending invocation
lease are intended to satisfy this contract. If the test fails, keep the fix
at the demonstrated lifetime boundary: deactivate before waiting, retain
pending invocation handles until RTT completion, and remove nodes only after
leases reach zero. Do not add sleeps or extend the request timeout to hide the
race.

- [ ] **Step 6: Commit package changes by ownership**

```bash
git -C toolchain/tools/ocl add \
  deployment/OpcUaDeploymentComponent.cpp \
  deployment/tests/opcua_deployment_test.cpp deployment/CMakeLists.txt
git -C toolchain/tools/ocl commit \
  -m "test: cover OPC UA freeze and unload lifetime"
```

If `rtt_opcua` production code changed, commit its test and fix separately:

```bash
git -C toolchain/tools/rtt_opcua add src tests
git -C toolchain/tools/rtt_opcua commit \
  -m "fix: retain timed out OPC UA invocation leases"
```

### Task 6: Stop `deployer-opcua` From Starting Automatically

**Files:**

- Modify: `toolchain/tools/ocl/bin/deployer.cpp`
- Modify: `tools/test-opcua-custom-datatypes.sh`

- [ ] **Step 1: Add an installed executable regression check first**

In `tools/test-opcua-custom-datatypes.sh`, launch the installed target-specific
`deployer-opcua` on a fresh loopback port with no startup script. Give it an
isolated `HOME` and the already constructed temporary runtime paths. Assert the
process remains alive but a TCP connection to the configured port fails. Send
`SIGTERM`, wait for clean shutdown, and print its log on failure.

- [ ] **Step 2: Run the check against the old executable**

```bash
OPCUA_VERIFY_ROOT="$(mktemp -d /tmp/orocos-opcua-explicit.XXXXXX)"
./tools/test-opcua-custom-datatypes.sh \
  --prefix "$OPCUA_VERIFY_ROOT/install" \
  --dependency-prefix "$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  --target gnulinux
```

Expected: the stopped-endpoint assertion fails because the executable calls
`dc.startOpcUa()` after processing scripts.

- [ ] **Step 3: Remove only the automatic startup block**

Delete the `#ifdef OCL_OPCUA_DEPLOYER` block after script processing that calls
`dc.startOpcUa()` and logs `Listening on`. Keep script error propagation,
interactive TaskBrowser creation, non-TTY `waitForInterrupt()`, and normal
shutdown unchanged.

- [ ] **Step 4: Re-run the installed stopped-endpoint check**

Expected: the Deployer remains usable locally, the process stays alive, and no
listener exists until a script or the local TaskBrowser calls `opcua.start()`.

- [ ] **Step 5: Commit executable and root regression independently**

```bash
git -C toolchain/tools/ocl add bin/deployer.cpp
git -C toolchain/tools/ocl commit \
  -m "fix: require explicit OPC UA deployer startup"
git add tools/test-opcua-custom-datatypes.sh
git commit -m "test: verify OPC UA deployer stays stopped"
```

### Task 7: Exercise Import, Load, Start, And Publish From The Installed Prefix

**Files:**

- Create: `tests/opcua-custom-datatypes/fixture_component.hpp`
- Create: `tests/opcua-custom-datatypes/fixture_component_plugin.cpp`
- Create: `tests/opcua-custom-datatypes/deployer-start.ops.in`
- Create: `tests/opcua-custom-datatypes/deployer-no-start.ops.in`
- Modify: `tests/opcua-custom-datatypes/fixture_component.cpp`
- Modify: `tests/opcua-custom-datatypes/fixture_types.hpp`
- Modify: `tests/opcua-custom-datatypes/fixture_typekit.cpp`
- Modify: `tests/opcua-custom-datatypes/fixture_client.cpp`
- Modify: `tests/opcua-custom-datatypes/CMakeLists.txt`
- Modify: `tools/test-opcua-custom-datatypes.sh`

**Interfaces:**

- Loadable component type:
  `orocos::opcua::fixture::FixtureComponent`
- Intentionally unsupported component type:
  `orocos::opcua::fixture::UnsupportedComponent`
- Runtime instance names: `sample` and `unsupported`

- [ ] **Step 1: Refactor the fixture component into shared test code**

Move the current `Surface<T>` and `FixtureComponent` definitions into
`fixture_component.hpp`. Give `FixtureComponent` the normal loadable signature:

```cpp
explicit FixtureComponent(const std::string &name = "fixture/component");
```

Keep the standalone `fixture-server` using this class so the existing direct
server/client custom-datatype test remains intact.

- [ ] **Step 2: Add a loadable component library and unknown RTT type**

Define `UnsupportedValue` in `fixture_types.hpp` and register it in the fixture
typekit without an OPC UA protocol. Define `UnsupportedComponent` with one
property of that type. In `fixture_component_plugin.cpp`, export both component
types:

```cpp
ORO_CREATE_COMPONENT_LIBRARY()
ORO_LIST_COMPONENT_TYPE(orocos::opcua::fixture::FixtureComponent)
ORO_LIST_COMPONENT_TYPE(orocos::opcua::fixture::UnsupportedComponent)
```

Add an `orocos_component` target to the fixture CMake project and include it in
the warnings-as-errors loop. Confirm installation places the library in the
fixture package component path discoverable by OCL `import()`.

- [ ] **Step 3: Generate two exact startup scripts**

`deployer-no-start.ops.in`:

```text
import("orocos_opcua_fixture")
loadComponent("sample", "orocos::opcua::fixture::FixtureComponent")
```

`deployer-start.ops.in`:

```text
import("orocos_opcua_fixture")
loadComponent("sample", "orocos::opcua::fixture::FixtureComponent")
loadComponent("unsupported", "orocos::opcua::fixture::UnsupportedComponent")
opcua.start()
opcua.publishComponent("sample")
```

The import deliberately precedes the first start so the fixture provider and
protocols are registered before the process-wide registry freezes.

- [ ] **Step 4: Extend the client to validate the Deployer and sample**

Add `--component` and `--deployer` arguments to `fixture-client`. Connect to
the Deployer proxy and assert its `connect`, `stream`, and `createStream`
operations are present. On the `opcua` service, assert exact lifecycle
operations, call `publishComponent("unsupported")`, and require false plus a
diagnostic naming the unsupported property and RTT type. Confirm no proxy can
be created for `unsupported`.

Then connect to `sample` and run the existing operation, property, attribute,
and port round trips for canonical and fixture custom datatypes. Continue to
validate custom DataType and encoding NodeIds from the server namespace table.

- [ ] **Step 5: Run both deployer modes in the root verifier**

First launch with `deployer-no-start.ops` and prove the port stays closed.
Then launch a fresh process with `deployer-start.ops`, wait for the loopback
endpoint, and run `fixture-client --deployer Deployer --component sample`.
Capture separate logs and always terminate/wait through the existing trap.

Keep the original standalone `fixture-server` pass as a lower-level transport
test; the deployer pass is additional coverage, not a replacement.

At the end of a successful run, write
`$TEST_ROOT/runtime-env.sh` with shell-quoted values for the temporary `HOME`,
`OROCOS_TARGET`, `PATH`, `LD_LIBRARY_PATH`, `RTT_COMPONENT_PATH`,
`CMAKE_PREFIX_PATH`, and `PKG_CONFIG_PATH` already used by the verifier. This
file is evidence and a convenience for manual acceptance; it must refer only
to the selected install/dependency prefixes below `/tmp`.

- [ ] **Step 6: Run the complete installed-prefix verification**

```bash
OPCUA_VERIFY_ROOT="$(mktemp -d /tmp/orocos-opcua-deployer.XXXXXX)"
./tools/test-opcua-custom-datatypes.sh \
  --prefix "$OPCUA_VERIFY_ROOT/install" \
  --dependency-prefix "$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  --target gnulinux
```

Expected terminal lines include both:

```text
OPC UA external custom datatype fixture passed
OPC UA deployer lifecycle fixture passed
```

The contamination scan must report no artifact resolved below `~/.orocos`.

- [ ] **Step 7: Commit the external acceptance fixture**

```bash
git add tests/opcua-custom-datatypes tools/test-opcua-custom-datatypes.sh
git commit -m "test: exercise explicit OPC UA deployer lifecycle"
```

### Task 8: Run Final Sanitizer And Manual TaskBrowser Acceptance

**Files:**

- Modify: `docs/src/opcua-deployer-lifecycle-design.md`
- Modify: `docs/src/user-guide.md`
- Modify: `docs/src/package-test-results.md`
- Modify: `tools/check-package-tests-ci.rb`
- Modify if the focused OCL test names changed:
  `tools/test-package.sh`
- Modify if the focused OCL test names changed:
  `tools/check-autoproj-policy.rb`

- [ ] **Step 1: Run the verifier with warnings as errors**

Create new directories; do not reuse evidence from an earlier task:

```bash
OPCUA_FINAL_ROOT="$(mktemp -d /tmp/orocos-opcua-final.XXXXXX)"
./tools/test-opcua-custom-datatypes.sh \
  --prefix "$OPCUA_FINAL_ROOT/install" \
  --dependency-prefix "$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  --target gnulinux
```

Record the exact prefix, evidence directory, CTest totals, and fixture output.

- [ ] **Step 2: Repeat the maintained graph under ASan/UBSan/LSan**

```bash
OPCUA_SAN_ROOT="$(mktemp -d /tmp/orocos-opcua-sanitized.XXXXXX)"
CXXFLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer' \
LDFLAGS='-fsanitize=address,undefined' \
ASAN_OPTIONS='detect_leaks=1:halt_on_error=1' \
UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1' \
./tools/test-opcua-custom-datatypes.sh \
  --prefix "$OPCUA_SAN_ROOT/install" \
  --dependency-prefix "$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  --target gnulinux
```

Expected: all RTT, `rtt_opcua`, OCL, standalone fixture, and deployer fixture
checks pass with no sanitizer report. If leak detection is unavailable on a
target, record that as a gap rather than silently disabling it.

- [ ] **Step 3: Manually validate local and remote TaskBrowsers**

Using the fresh final prefix, source the generated temporary runtime file and
start the target binary in a PTY:

```bash
. "$OPCUA_FINAL_ROOT/install-work/runtime-env.sh"
"$OPCUA_FINAL_ROOT/install/bin/deployer-opcua-gnulinux" --opcua-port 4841
```

In its local TaskBrowser, enter exactly:

```text
import("orocos_opcua_fixture")
loadComponent("sample", "orocos::opcua::fixture::FixtureComponent")
opcua.start()
opcua.publishComponent("sample")
```

Before `opcua.start()`, verify a remote client cannot connect. After
publication, open a second PTY with the same temporary runtime paths:

```bash
. "$OPCUA_FINAL_ROOT/install-work/runtime-env.sh"
"$OPCUA_FINAL_ROOT/install/bin/ctaskbrowser-opcua-gnulinux" \
  --import orocos_opcua_fixture \
  opc.tcp://127.0.0.1:4841/rtt sample
```

Browse/call one operation and write/read one property or attribute. Connect a
second `ctaskbrowser-opcua` to component `Deployer` and verify the `opcua`
service plus the full `connect`/`stream`/`createStream` operations.

- [ ] **Step 4: Update documentation and CI contract names**

Set the lifecycle design status to `Accepted`. Update the user guide to show
the import/load/start/publish order and state that the remote TaskBrowser
cannot connect before start. Replace stale queued, automatic, `publishPeer`,
and partial-publication claims in package results.

Update root package-test regexes to match
`^ocl_opcua_deployment_.*$`. Keep the build target
`ocl_opcua_deployment_test`; only CTest case names are split.

- [ ] **Step 5: Build docs and run policy checks**

```bash
DOC_ROOT="$(mktemp -d /tmp/orocos-opcua-docs.XXXXXX)"
mdbook build docs --dest-dir "$DOC_ROOT/book"
ruby tools/check-package-tests-ci.rb
ruby tools/check-autoproj-policy.rb
```

Expected: mdBook emits no warning, both policy scripts exit zero, and searches
find no stale public API names:

```bash
rg -n 'publishPeer|unpublishPeer|automatically starts|queued publication' \
  docs/src toolchain/tools/ocl/deployment toolchain/tools/ocl/bin
```

Only explicitly historical/superseded design text may remain.

- [ ] **Step 6: Commit root documentation and verification metadata**

```bash
git add \
  docs/src/opcua-deployer-lifecycle-design.md \
  docs/src/user-guide.md docs/src/package-test-results.md \
  tools/check-package-tests-ci.rb tools/test-package.sh \
  tools/check-autoproj-policy.rb
git commit -m "docs: finalize explicit OPC UA deployer lifecycle"
```

- [ ] **Step 7: Perform the pre-merge review checkpoint**

Invoke `superpowers:requesting-code-review`, inspect every package and root
diff, and summarize:

- commits per repository
- behavior/API changes
- fresh unit, integration, sanitizer, and manual evidence
- dependency versions and CORBA-off configuration
- proof that no test resolved `~/.orocos`
- warnings or validation gaps, including Xenomai work still requiring the
  user's other machine

Stop here. Do not merge or push default branches until the user reviews this
summary and explicitly approves integration.
