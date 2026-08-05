# OPC UA Static Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Use
> `superpowers:test-driven-development` for every behavior change and
> `superpowers:verification-before-completion` before claiming a task or the
> plan complete.

**Goal:** Replace the current dynamic OPC UA registration and reconciliation
model with the approved explicit-start, strict, publish-once component model,
while preserving the generic datatype, proxy, operation, and latest-value port
support already implemented.

**Architecture:** `rtt_opcua::ObjectModel` validates and creates each complete
component subtree once, owns it until endpoint teardown, and never reconciles,
replaces, or publicly removes it. OCL's `OpcUaDeploymentComponent` freezes the
datatype registry on the first explicit `opcua.start()` attempt, starts the
loopback server, publishes only its Deployer, and explicitly publishes named
local components. OCL rejects Deployer-managed unloads of published
components. Timed-out OwnThread calls are reaped independently of graph
maintenance and retain all RTT state until completion.

**Tech Stack:** C++20, Orocos RTT/OCL, stock open62541 `v1.4.15`, stock
open62541pp `v0.21.2`, CMake, Boost.Test, Ruby policy checks, mdBook,
AddressSanitizer, UndefinedBehaviorSanitizer, and LeakSanitizer.

## Global Constraints

- Work only in the linked root, RTT, `rtt_opcua`, and OCL
  `codex/orocos-opcua-custom-datatypes` worktrees.
- Preserve unrelated edits. In particular, retain the pre-existing direct
  `<stdexcept>` include in OCL's `deployment/OpcUaDeploymentComponent.cpp`;
  because Task 4 modifies that same file, keep the include in the resulting
  OCL commit and call it out in the final review. Do not stage the user's
  `docs/src/SUMMARY.md` or
  `docs/src/opcua-web-gateway-plan.md` changes with this work.
- Consume official open62541 `v1.4.15` and open62541pp `v0.21.2` source without
  modification. Do not merge, push, or select the experimental dependency
  worktree branches.
- Configure `UA_BUILD_UNIT_TESTS=OFF` and `UAPP_BUILD_TESTS=OFF`. Maintained
  RTT, `rtt_opcua`, OCL, executable, and external-fixture tests cover the
  required behavior.
- Never install into, source from, or resolve packages from `~/.orocos`.
  Authoritative build trees, installs, isolated `HOME`, logs, caches, source
  checkouts, ready files, and runtime data must be below one new `/tmp`
  directory.
- Build the maintained code as C++20 with its warning-as-error policy. Keep
  CORBA source available but configure this workspace with `ENABLE_CORBA=OFF`.
- Keep the already implemented generic `RTT::ConnPolicy` mapping and the
  latest-value RTT port contract. Do not reinterpret an RTT object containing
  `std::string` as an open62541 structure.
- Publish the full supported RTT interface. Do not add an allowlist,
  publication modes, `Server=true` auto-publication, queued publication, a
  public stop operation, PKI, non-loopback listening, RBAC, or late datatype
  registration.
- Do not implement `unpublishComponent`, replacement, reconciliation, or
  unload-after-publication in this version. Internal rollback of a failed
  candidate publication is required and is not public unpublication.
- A non-returning RTT OwnThread operation may delay shutdown. Never release
  its component lease, arguments, result storage, or send handle early.
- Commit changes in the owning package after each green task. Do not merge or
  push default branches until Task 8 provides a package-by-package review and
  the user approves integration.
- These eight tasks are generic toolchain work. MetaNC migration work remains
  excluded and will use a separate handoff/session.

## Worktree And Temporary Environment

Run all commands from the root feature worktree unless a step explicitly uses
`git -C`. At the start of execution, create and retain one isolated root:

```bash
export OROCOS_OPCUA_VERIFY_ROOT="$(mktemp -d /tmp/orocos-opcua-static.XXXXXX)"
export OROCOS_OPCUA_DEPENDENCY_PREFIX="$OROCOS_OPCUA_VERIFY_ROOT/dependencies"
export OROCOS_OPCUA_INSTALL_PREFIX="$OROCOS_OPCUA_VERIFY_ROOT/install"
export OROCOS_OPCUA_TEST_HOME="$OROCOS_OPCUA_VERIFY_ROOT/home"
mkdir -p "$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  "$OROCOS_OPCUA_INSTALL_PREFIX" "$OROCOS_OPCUA_TEST_HOME"
```

Never substitute an existing non-empty prefix. Record the concrete generated
path in the final verification evidence so another machine can distinguish
source revisions from local artifacts.

## File Responsibility Map

| Layer | Owns | Must not own |
|---|---|---|
| Root policy | source pins, build options, verification harness, evidence | runtime publication logic |
| `rtt_opcua` | strict snapshot, node creation transaction, codecs, callbacks, proxy | OCL component lookup or unload policy |
| OCL deployment | explicit endpoint state, component lookup, publication registry, unload guard | OPC UA node construction |
| External fixture | installed-package acceptance from a clean consumer | private source-tree linkage or MetaNC types |

---

## Task 1: Select Unmodified Stock OPC UA Dependencies

**Files:**

- Modify: `autoproj/overrides.yml`
- Modify: `tools/check-autoproj-policy.rb`
- Modify: `docs/src/package-policy.md`

**Consumes:** the existing Autoproj package order and the already correct
`UA_BUILD_UNIT_TESTS=OFF`, `UAPP_BUILD_TESTS=OFF`, and
`UAPP_INTERNAL_OPEN62541=OFF` definitions in `autoproj/local.autobuild`.

**Produces:** reproducible official tag selections:

```yaml
- open62541:
  type: git
  url: https://github.com/open62541/open62541.git
  tag: v1.4.15

- open62541pp:
  type: git
  url: https://github.com/open62541pp/open62541pp.git
  tag: v0.21.2
```

- [ ] **Step 1: Make the policy check require official immutable tags**

In `tools/check-autoproj-policy.rb`, replace the two dependency entries in
`expected_forks` with `tag` entries and rename the map to `expected_sources`.
Keep every modified first-party package on its `liufang-robot` source and
`dev` branch. Add explicit assertions that `local.autobuild` contains:

```ruby
'pkg.define "UA_BUILD_UNIT_TESTS", "OFF"'
'pkg.define "UAPP_BUILD_TESTS", "OFF"'
'pkg.define "UAPP_INTERNAL_OPEN62541", "OFF"'
```

- [ ] **Step 2: Run the policy check and observe the source mismatch**

```bash
ruby tools/check-autoproj-policy.rb
```

Expected: failure reports that open62541 and open62541pp still use the
`liufang-robot` branch selections instead of the official tags.

- [ ] **Step 3: Change only the selected dependency sources**

Update `autoproj/overrides.yml` to the exact official URLs and tags above.
Do not change the `liufang-robot` selections for RTT, `rtt_opcua`, OCL,
oroGen, Typelib, utilmm, or `rtt_typelib`.

Rewrite the dependency paragraph in `docs/src/package-policy.md` so it states:

- official tags are consumed unchanged;
- dependency tests are disabled;
- maintained integration tests prove the used behavior; and
- experimental local dependency branches are neither selected nor published.

- [ ] **Step 4: Prove the policy and working-tree boundary**

```bash
ruby tools/check-autoproj-policy.rb
rg -n 'open62541(pp)?' autoproj/overrides.yml autoproj/local.autobuild \
  docs/src/package-policy.md
git status --short
git diff --check
```

Expected: policy check exits zero; both official tags are visible; both
dependency test options are `OFF`; no open62541/open62541pp source file is
staged or modified by this task.

- [ ] **Step 5: Commit the root policy change**

```bash
git add autoproj/overrides.yml tools/check-autoproj-policy.rb \
  docs/src/package-policy.md
git commit -m "build: use stock pinned OPC UA dependencies"
```

---

## Task 2: Replace Dynamic Registration With Static Publication

**Files:**

- Modify: `toolchain/tools/rtt_opcua/include/rtt/opcua/object_model.hpp`
- Modify: `toolchain/tools/rtt_opcua/include/rtt/opcua/server.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/server.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`

**Consumes:** the existing strict snapshot builder, `UnsupportedResource`,
component callback state and leases, operation dispatcher, port bridge,
deterministic NodeIds, endpoint type registry, and `RTT::ConnPolicy` codec.

**Produces:** this public `rtt_opcua` API:

```cpp
struct ObjectModelOptions {
  std::chrono::milliseconds operation_timeout{std::chrono::seconds(5)};
  std::size_t port_buffer_size{64U};
  std::function<void(const std::string &)> warning_sink;
};

class ObjectModel final {
public:
  explicit ObjectModel(Server &server, ObjectModelOptions options = {});
  ~ObjectModel();

  bool publishComponent(
      RTT::TaskContext &component,
      std::string *error = nullptr,
      std::vector<UnsupportedResource> *unsupported = nullptr);
  std::uint64_t revision() const noexcept;
  std::size_t componentCount() const noexcept;
  std::size_t pendingOperationCount() const noexcept;
  std::vector<UnsupportedResource>
  unsupportedResources(std::string_view component) const;
  std::string lastError() const;
};
```

`ComponentRegistration`, `registerComponent`, `reconcile`,
`reconcile_interval`, and `Server::retainUntilStopped` cease to exist.

- [ ] **Step 1: Replace reconciliation cases with static-contract tests**

Keep the canonical array, strict unsupported-type, invalid-option, complete
snapshot, operation, port, and callback-failure coverage in
`tests/object_model_test.cpp`. Delete tests whose required outcome is graph
reconciliation, registration-reset removal, ownership abandonment,
replacement, or live resource refresh. Add these cases:

```text
publish_component_creates_one_complete_static_snapshot
publish_component_is_idempotent_for_the_same_instance
publish_component_rejects_a_different_instance_with_the_same_name
unsupported_resource_rejects_the_whole_component
creation_failure_rolls_back_only_candidate_nodes
resource_changes_after_publication_do_not_change_topology
```

Assertions shared by the cases:

- a successful first publication increments revision once and component count
  once;
- same-instance publication returns true without changing revision;
- same-name/different-pointer publication returns false and preserves the
  first model;
- strict preflight failure leaves no component root and caches every
  diagnostic;
- `UnsupportedResource::message()` says `rejected`, not `skipped`; and
- adding an RTT resource later does not create a node or change revision.

For rollback, create a foreign OPC UA node whose NodeId equals a later
candidate property NodeId, but parent it under `ObjectsFolder`. Publish a
component containing that property. Assert that the collision makes
publication fail, every earlier candidate node is gone, and the foreign node
still exists with its original value and parent.

Update `tests/task_context_proxy_test.cpp` to call `publishComponent`. Remove
registration resets and republishing. Keep repeated
`TaskContextProxy::synchronize()` calls as client-only synchronization against
an unchanged server graph.

- [ ] **Step 2: Build the tests and observe the obsolete API failures**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel \
  --target rtt_opcua_object_model_test rtt_opcua_task_context_proxy_test
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
  -R '^rtt_opcua_(object_model|task_context_proxy)_test$'
```

Expected: compilation fails because `ObjectModel::publishComponent` does not
exist and the old API still owns registration/reconciliation state.

- [ ] **Step 3: Reduce the public and internal state model**

Remove `ComponentRegistration` and its reset/unregister paths. Store successful
publications in `ObjectModelImpl` by component name with the original
`RTT::TaskContext*`, closed-capable callback state, port bridges, and immutable
snapshot fingerprint. Do not run a worker thread.

Implement the top-level decision in this order while holding the model command
mutex:

```cpp
bool ObjectModelImpl::publishComponent(
    RTT::TaskContext &component,
    std::string *error,
    std::vector<UnsupportedResource> *unsupported) {
  // 1. Return true for the already-published same pointer.
  // 2. Reject a name already bound to a different pointer.
  // 3. Build and strictly validate the complete snapshot.
  // 4. Create the candidate subtree transactionally.
  // 5. Commit callback/bridge ownership and increment revision once.
}
```

On any false result, set both the returned error and `lastError()`. On success,
clear the cached error and the component's old unsupported diagnostics.

- [ ] **Step 4: Implement creation-only transaction rollback**

Replace reconciliation and adoption logic with a local creation ledger:

```cpp
struct CreatedNode {
  ::opcua::NodeId id;
  bool recursive_root{false};
};
```

Apply these rules:

- shared namespace roots may accept `BadNodeIdExists`, but are never entered
  into the ledger;
- every component-owned NodeId treats `BadNodeIdExists` as failure and never
  adopts the existing node;
- record only nodes successfully created by the current attempt;
- after method creation, browse and record its generated `InputArguments` and
  `OutputArguments` property NodeIds;
- rollback closes candidate callback state and deletes ledger entries in
  reverse order; deleting the component root recursively covers its owned
  descendants;
- ignore `BadNodeIdUnknown` only while rolling back an already removed
  descendant; report any other rollback failure; and
- never delete or rewrite pre-existing nodes.

The successful model owns callback and bridge state until its destructor.
Stock open62541pp callback adapter storage may remain inert until server
destruction; callbacks capture weak/closed component state, not a naked usable
component pointer.

- [ ] **Step 5: Remove server-side retention added for reconciliation**

Delete `Server::retainUntilStopped`, its retained-owner container, and every
call site. The caller owns `ObjectModel` explicitly. Preserve `Server::invoke`
semantics: once a task starts, a timeout must not invalidate synchronous
captures.

- [ ] **Step 6: Prove the static model and absence of dynamic APIs**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel \
  --target rtt_opcua_object_model_test rtt_opcua_task_context_proxy_test
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
  -R '^rtt_opcua_(object_model|task_context_proxy)_test$'
rg -n 'ComponentRegistration|registerComponent|reconcile_interval|reconcile\(|retainUntilStopped' \
  toolchain/tools/rtt_opcua/include toolchain/tools/rtt_opcua/src \
  toolchain/tools/rtt_opcua/tests
git -C toolchain/tools/rtt_opcua diff --check
```

Expected: both suites pass and `rg` returns no matches.

- [ ] **Step 7: Commit the `rtt_opcua` static graph**

```bash
git -C toolchain/tools/rtt_opcua add include/rtt/opcua/object_model.hpp \
  include/rtt/opcua/server.hpp src/object_model.cpp src/server.cpp \
  tests/object_model_test.cpp tests/task_context_proxy_test.cpp
git -C toolchain/tools/rtt_opcua commit -m \
  "refactor: make OPC UA component publication static"
```

---

## Task 3: Reap Timed-Out Operations Without Graph Maintenance

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/operation_dispatcher.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/operation_dispatcher.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`

**Consumes:** `PendingInvocation`, which already owns the `ComponentLease`,
`SendHandleC`, argument datasources, and result datasources needed after an OPC
UA request returns `BadTimeout`.

**Produces:** automatic pending-call cleanup independent of reconciliation and
blocking lifetime-safe drain during object-model destruction.

- [ ] **Step 1: Add the two operation-lifetime regression tests**

Add:

```text
timed_out_operation_is_reaped_without_graph_activity
shutdown_after_timeout_waits_for_operation_completion
```

The first test invokes a deliberately delayed OwnThread operation with a short
OPC UA timeout, asserts `BadTimeout`, releases the operation, and waits with a
bounded polling helper until `pendingOperationCount() == 0`. It must not call a
model reconciliation or reaping method.

The second test starts the delayed call, observes `BadTimeout`, immediately
stops the server and destroys the model on another thread, and asserts that
destruction remains blocked until the delayed RTT operation is released. Then
join all threads and assert the operation completed exactly once.

- [ ] **Step 2: Run the focused test and observe stale pending state**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel \
  --target rtt_opcua_object_model_test
toolchain/tools/rtt_opcua/build/rtt_opcua_object_model_test \
  --run_test=timed_out_operation_is_reaped_without_graph_activity
```

Expected: the pending count does not return to zero because the removed graph
worker was the only periodic reaper.

- [ ] **Step 3: Give `OperationDispatcher` a focused reaper**

Add `std::condition_variable`, `std::jthread`, and a `draining` flag to
`OperationDispatcher::Impl`. The reaper sleeps while no calls are pending,
wakes after `retain`, probes `collectIfDone()`, erases completed handles, and
never reads or mutates OPC UA topology.

Use this shutdown order:

```cpp
void OperationDispatcher::Impl::drain() noexcept {
  {
    std::lock_guard lock(mutex);
    draining = true;
  }
  reaper.request_stop();
  wake.notify_all();
  if (reaper.joinable()) {
    reaper.join();
  }
  while (count() != 0U) {
    reapOnce();
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}
```

If `retain` races with `drain`, do not append after draining starts; wait on
that invocation locally until its handle finishes. Keep all exception
boundaries `noexcept` and treat a collect exception as a finished invocation.
Remove public/internal `reapPending()` calls from ObjectModel; retain only the
pending count observation needed by tests.

- [ ] **Step 4: Run focused and complete maintained `rtt_opcua` tests**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
  -R '^rtt_opcua_.*_test$'
git -C toolchain/tools/rtt_opcua diff --check
```

Expected: both new lifetime cases and the full maintained suite pass; no test
invokes reconciliation to release a timed-out call.

- [ ] **Step 5: Commit the dispatcher lifetime change**

```bash
git -C toolchain/tools/rtt_opcua add src/operation_dispatcher.hpp \
  src/operation_dispatcher.cpp tests/object_model_test.cpp
git -C toolchain/tools/rtt_opcua commit -m \
  "fix: retain timed out OPC UA calls through completion"
```

---

## Task 4: Make OCL Startup And Publication Explicit

**Files:**

- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.hpp`
- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.cpp`
- Modify: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`
- Modify: `toolchain/tools/ocl/deployment/CMakeLists.txt`
- Modify: `toolchain/tools/ocl/bin/deployer.cpp`

**Consumes:** `RTT::opcua::Server`, the static `ObjectModel`, process-wide
datatype registry, local Deployer peer map, and existing remote proxy methods.

**Produces:** the exact local `opcua` service:

```text
bool start()
bool isRunning()
String endpointUrl()
String lastError()
bool publishComponent(String component)
StringArray unsupportedResources(String component)
```

There is no `ready`, `endpoint`, `publishPeer`, `unpublishPeer`, or
`unpublishComponent` compatibility operation.

- [ ] **Step 1: Split the deployment tests into process-isolated cases**

Replace the broad old lifecycle cases with:

```text
explicit_start_publishes_only_deployer
strict_publication_is_static_and_idempotent
server_metadata_does_not_auto_publish
failed_start_freezes_registry_and_can_retry
remote_components_remain_aliased_client_peers
```

Register each Boost case as a separate CTest process because the datatype
registry freezes process-wide:

```cmake
foreach(case IN ITEMS
    explicit_start_publishes_only_deployer
    strict_publication_is_static_and_idempotent
    server_metadata_does_not_auto_publish
    failed_start_freezes_registry_and_can_retry
    remote_components_remain_aliased_client_peers)
  add_test(
    NAME ocl_opcua_deployment_${case}
    COMMAND ocl_opcua_deployment_test --run_test=${case})
endforeach()
```

The first case asserts construction is stopped, `endpointUrl()` is already
available, pre-start publication returns false without queueing, start
publishes only `Deployer`, repeated start is a true no-op, and service
introspection exposes exactly the six operations above.

The strict case verifies supported publication, same-instance idempotency,
remote value/operation access, complete rejection of an unsupported type,
queryable diagnostics, no residual subtree, and fixed topology after adding a
late RTT resource.

The metadata case loads a site component with `Server=true`, starts the
endpoint, proves the component is absent, then explicitly publishes it.

The failed-start case occupies the configured loopback port, calls start,
asserts the registry remains frozen, releases the port, and retries
successfully with the same frozen registry.

- [ ] **Step 2: Run the new tests and observe old lifecycle behavior**

```bash
cmake --build toolchain/tools/ocl/build --parallel \
  --target ocl_opcua_deployment_test deployer-opcua
ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
  -R '^ocl_opcua_deployment_.*$'
```

Expected: cases fail to compile against the new method names or fail because
construction queues publications and the executable still starts OPC UA
automatically.

- [ ] **Step 3: Implement the explicit lifecycle state machine**

Use internal states `created`, `starting`, `running`, `start_failed`,
`stopping`, and `destroyed`. Serialize lifecycle and publication commands with
one mutex. Store successful publications as
`std::map<std::string, RTT::TaskContext*, std::less<>>`.

Expose these C++ backing methods:

```cpp
bool startOpcUa();
bool opcUaIsRunning() const;
std::string opcUaEndpointUrl() const;
std::string opcUaLastError() const;
bool publishComponent(const std::string &component_name);
std::vector<std::string>
unsupportedResources(const std::string &component_name) const;
```

Constructor behavior is limited to creating the server configuration, adding
the six service operations, and preserving remote-client services. It must not
start the server, queue Deployer publication, iterate loaded peers, or inspect
`Server=true`.

Implement `startOpcUa()` synchronously in this order:

```text
registerCanonicalTypeProtocols
freezeDataTypeRegistry
Server::start
construct ObjectModel
ObjectModel::publishComponent(*this)
record Deployer publication
state = running
```

On the first attempt, register the canonical protocols and freeze the
registry. On retries, the same-registration checks and
`freezeDataTypeRegistry()` must be idempotent; no retry may reopen or mutate
the registry.

On a failure after the listener starts, stop the listener, destroy the
candidate ObjectModel, leave the datatype registry frozen, set
`state = start_failed`, and retain an exact `lastError`. A later start retries
using the same configuration and frozen registry. Starting while running
returns true without changing the model revision.

- [ ] **Step 4: Implement strict named publication**

Before running, return false with `OPC UA server is not running`. While
running, resolve `Deployer` or a known local peer. Reject an unknown name and
reject `RTT::opcua::TaskContextProxy` instances. Forward to
`ObjectModel::publishComponent`, cache diagnostics, and record the pointer only
after success. A successful command clears `lastError`.

`componentLoaded` continues only the existing remote-proxy bookkeeping. It
does not publish local peers. Remove OPC UA auto-unpublication from
`componentUnloaded`; Task 5 supplies the pre-unload safety guard.

- [ ] **Step 5: Remove executable auto-start**

Delete the `deployer.cpp` block that calls `dc.startOpcUa()` after processing
the supplied `.ops`/site files. The deployment script or interactive local
TaskBrowser must issue `opcua.start()` explicitly. A script containing only
`import` and `loadComponent` must leave the configured port closed.

- [ ] **Step 6: Prove the service and executable contract**

```bash
cmake --build toolchain/tools/ocl/build --parallel \
  --target ocl_opcua_deployment_test deployer-opcua ctaskbrowser-opcua
ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
  -R '^(ocl_opcua_deployment_.*|ctaskbrowser_opcua_.*)$'
rg -n 'publishPeer|unpublishPeer|ComponentRegistration|reconcile_interval' \
  toolchain/tools/ocl/deployment toolchain/tools/ocl/bin
git -C toolchain/tools/ocl diff --check
```

Expected: tests pass and `rg` returns no matches. Strings asserting the absence
of historical service names are allowed only in tests.

- [ ] **Step 7: Commit the OCL lifecycle change**

```bash
git -C toolchain/tools/ocl add deployment/OpcUaDeploymentComponent.hpp \
  deployment/OpcUaDeploymentComponent.cpp \
  deployment/tests/opcua_deployment_test.cpp deployment/CMakeLists.txt \
  bin/deployer.cpp
git -C toolchain/tools/ocl commit -m \
  "refactor: make OPC UA deployment startup explicit"
```

---

## Task 5: Reject Deployer-Managed Unload Of Published Components

**Files:**

- Modify: `toolchain/tools/ocl/deployment/DeploymentComponent.hpp`
- Modify: `toolchain/tools/ocl/deployment/DeploymentComponent.cpp`
- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.hpp`
- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.cpp`
- Modify: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`
- Modify: `toolchain/tools/ocl/deployment/CMakeLists.txt`

**Consumes:** the ordinary `DeploymentComponent::unloadComponentImpl` path and
the static publication pointer map from Task 4.

**Produces:** a default-allow unload hook used by all ordinary Deployer unload
entry points:

```cpp
protected:
  virtual bool componentCanUnload(RTT::TaskContext *component);
```

- [ ] **Step 1: Add a factory-backed unload test**

Add `published_component_unload_is_rejected` as another isolated CTest case.
Register an `EchoTask` factory with `ComponentLoader`, then assert:

1. an unpublished loaded component unloads successfully;
2. a second loaded component publishes successfully;
3. `unloadComponent` for the published component returns false;
4. `lastError()` is exactly
   `Cannot unload component 'ManagedEcho': it is published through OPC UA`;
5. the component remains a Deployer peer; and
6. its remote proxy still performs an operation after the rejection.

Use fixture cleanup that unregisters the factory after the Deployer is
destroyed. Do not directly delete a component still owned by
`ComponentLoader`.

- [ ] **Step 2: Run the case and observe destructive unload**

```bash
cmake --build toolchain/tools/ocl/build --parallel \
  --target ocl_opcua_deployment_test
ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
  -R '^ocl_opcua_deployment_published_component_unload_is_rejected$'
```

Expected: the old unload path destroys the published component or leaves the
test unable to call it remotely.

- [ ] **Step 3: Add the pre-unload hook at the common boundary**

Implement `DeploymentComponent::componentCanUnload` to return true. In
`unloadComponentImpl`, call it after confirming the component is loaded and
not running, but before `componentUnloaded`, disconnect, activity deletion,
connection-map changes, property removal, or `ComponentLoader` deletion:

```cpp
if (!componentCanUnload(it->instance)) {
  return false;
}
```

This location automatically covers `unloadComponent`, group unload, and
`kickOut` flows that use `unloadComponentImpl`, without changing CORBA's
existing `componentUnloaded` behavior.

- [ ] **Step 4: Override the hook for static OPC UA publications**

Under the deployment mutex, compare both component name and pointer with the
publication map. Reject only an exact published local instance, set/log the
required diagnostic, and return false. Allow unpublished local components and
remote proxies.

In `OpcUaDeploymentComponent` destruction, reject new callbacks, stop the
server, wait for retained operations, reset the ObjectModel, and clear the
publication map before the base `DeploymentComponent` destructor performs
ordinary auto-unload.

- [ ] **Step 5: Run OCL deployment and existing unload coverage**

```bash
cmake --build toolchain/tools/ocl/build --parallel
ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
  -R '^(ocl_opcua_deployment_.*|deployment.*|load.*component.*)$'
git -C toolchain/tools/ocl diff --check
```

Expected: the new rejection case and maintained deployment unload cases pass;
non-OPC-UA deployers retain default unload behavior.

- [ ] **Step 6: Commit the unload guard**

```bash
git -C toolchain/tools/ocl add deployment/DeploymentComponent.hpp \
  deployment/DeploymentComponent.cpp deployment/OpcUaDeploymentComponent.hpp \
  deployment/OpcUaDeploymentComponent.cpp \
  deployment/tests/opcua_deployment_test.cpp deployment/CMakeLists.txt
git -C toolchain/tools/ocl commit -m \
  "fix: keep published OPC UA components loaded"
```

---

## Task 6: Prove The Installed Deployer Flow With An External Fixture

**Files:**

- Create: `tests/opcua-custom-datatypes/fixture_components.hpp`
- Create: `tests/opcua-custom-datatypes/fixture_components.cpp`
- Create: `tests/opcua-custom-datatypes/fixture_plugin.cpp`
- Rename: `tests/opcua-custom-datatypes/fixture_component.cpp` to
  `tests/opcua-custom-datatypes/fixture_server.cpp`
- Create: `tests/opcua-custom-datatypes/deployer-no-start.ops`
- Create: `tests/opcua-custom-datatypes/deployer-start.ops`
- Modify: `tests/opcua-custom-datatypes/fixture_types.hpp`
- Modify: `tests/opcua-custom-datatypes/fixture_typekit.cpp`
- Modify: `tests/opcua-custom-datatypes/fixture_transport.cpp`
- Modify: `tests/opcua-custom-datatypes/fixture_client.cpp`
- Modify: `tests/opcua-custom-datatypes/CMakeLists.txt`
- Modify: `tests/opcua-custom-datatypes/package.xml`
- Modify: `tools/test-opcua-custom-datatypes.sh`

**Consumes:** installed RTT, `rtt_opcua`, and OCL packages only. The fixture
must not include private source-tree headers or MetaNC code.

**Produces:** a loadable supported component, a loadable intentionally
unsupported component, standalone server/client coverage, and an automated
`deployer-opcua` acceptance flow.

- [ ] **Step 1: Make the fixture expect the new installed API**

Use `git mv` for the standalone server source. Extract reusable
`FixtureComponent` and `UnsupportedComponent` declarations/definitions into
`fixture_components.hpp/.cpp`. Export both from `fixture_plugin.cpp`:

```cpp
ORO_CREATE_COMPONENT_LIBRARY()
ORO_LIST_COMPONENT_TYPE(orocos::opcua::fixture::FixtureComponent)
ORO_LIST_COMPONENT_TYPE(orocos::opcua::fixture::UnsupportedComponent)
```

Add `UnsupportedValue` to the fixture typekit, but deliberately omit its codec
from `fixture_transport.cpp`. Update the standalone server to call
`ObjectModel::publishComponent` and to stop the server before destroying its
model.

Extend `fixture_client` with mutually exclusive `--standalone` and
`--deployer` modes plus `--component NAME`. Deployer mode must remotely assert:

- the six exact `opcua` service operations;
- the complete Deployer operations, including ConnPolicy-taking connection
  operations;
- supported component operation, writable property, writable attribute,
  read-only constant, and latest-value ports;
- repeated `publishComponent(component)` succeeds;
- unsupported publication fails and diagnostics identify the exact resource;
- unloading the supported published component fails; and
- the supported component remains callable after unload rejection.

- [ ] **Step 2: Configure against the old installed API and observe failure**

```bash
cmake -S tests/opcua-custom-datatypes \
  -B "$OROCOS_OPCUA_VERIFY_ROOT/fixture-red" \
  -DCMAKE_PREFIX_PATH="$OROCOS_OPCUA_INSTALL_PREFIX;$OROCOS_OPCUA_DEPENDENCY_PREFIX"
cmake --build "$OROCOS_OPCUA_VERIFY_ROOT/fixture-red" --parallel
```

Expected: compilation fails until Tasks 2 through 5 have installed the new
API and the fixture build defines the new component plugin.

- [ ] **Step 3: Install the fixture component plugin and scripts**

In CMake, build `fixture-components` with `orocos_component`, link the reusable
implementation into the plugin and standalone server, apply C++20 plus
`-Wall -Wextra -Wpedantic -Werror`, and install both `.ops` scripts under
`share/orocos-opcua-fixture`.

The scripts contain only ordinary TaskBrowser commands. The no-start script
imports the fixture package and loads `sample` and `unsupported`; it never
calls `opcua.start()`. The start script performs:

```text
import("orocos_opcua_fixture")
loadComponent("sample", "orocos::opcua::fixture::FixtureComponent")
loadComponent("unsupported", "orocos::opcua::fixture::UnsupportedComponent")
opcua.start()
opcua.publishComponent("sample")
```

Do not rely on `Server=true`.

- [ ] **Step 4: Extend the root harness with both endpoint states**

Keep the existing prefix validation, empty-prefix requirement, isolated
`HOME`, CMake registry disablement, CORBA-off RTT build, warning-as-error
flags, standalone server/client run, and cleanup traps.

After installing the fixture:

1. launch `deployer-opcua` with the no-start script, chosen loopback port, and
   non-TTY stdin so it waits for a signal;
2. prove the TCP port refuses connections and the client cannot create the
   Deployer proxy;
3. stop that process cleanly;
4. launch a new `deployer-opcua` with the start script and a fresh port;
5. wait for a positive OPC UA client probe rather than a log substring;
6. run `fixture-client --deployer --component sample`;
7. stop the process cleanly; and
8. write `$TEST_ROOT/runtime-env.sh` containing only the temporary prefix,
   endpoint, binary, plugin, and script paths used for optional manual review.

Update the OCL CTest regex to `^ocl_opcua_deployment_.*$`.

- [ ] **Step 5: Run the complete isolated installed-prefix acceptance**

First build the stock dependency prefix in Task 8, or point the variable to an
already verified stock prefix below `/tmp`. Then use a new empty maintained
install prefix:

```bash
OPCUA_ACCEPT_PREFIX="$(mktemp -d /tmp/orocos-opcua-accept.XXXXXX)"
./tools/test-opcua-custom-datatypes.sh \
  --prefix "$OPCUA_ACCEPT_PREFIX" \
  --dependency-prefix "$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  --target gnulinux
```

Expected: RTT, `rtt_opcua`, OCL, and fixture build/install under `/tmp`; the
stopped-endpoint negative case, standalone custom datatype case, explicit
Deployer start, strict rejection, unload rejection, and client checks all pass.

- [ ] **Step 6: Commit the root fixture change**

```bash
git add tests/opcua-custom-datatypes tools/test-opcua-custom-datatypes.sh
git commit -m "test: cover explicit OPC UA deployer publication"
```

---

## Task 7: Align CI Contracts And Operator Documentation

**Files:**

- Modify: `tools/check-package-tests-ci.rb`
- Modify: `tools/test-package.sh`
- Modify: `docs/src/user-guide.md`
- Modify: `docs/src/opcua-custom-datatype-verification.md`
- Modify: `docs/src/package-test-results.md`
- Modify: `docs/src/orocos-opcua-custom-datatype-design.md`
- Modify: `toolchain/tools/rtt_opcua/README.md`
- Modify if present: OCL OPC UA documentation that names the removed service
  operations

**Consumes:** green package and fixture behavior from Tasks 1 through 6.

**Produces:** one current operator contract and CI selectors that run every
isolated OCL lifecycle case.

- [ ] **Step 1: Make the CI contract require split OCL tests**

Change checks and `test-package.sh` from the single
`^ocl_opcua_deployment_test$` CTest name to
`^ocl_opcua_deployment_.*$`. Add a negative policy assertion that the custom
datatype harness does not configure `UA_BUILD_UNIT_TESTS=ON` or
`UAPP_BUILD_TESTS=ON`.

- [ ] **Step 2: Run the checker and observe the stale selector**

```bash
ruby tools/check-package-tests-ci.rb
```

Expected before the script/test command update: failure reports the obsolete
single OCL test selector.

- [ ] **Step 3: Document the exact startup and lifetime rules**

The user guide must show this sequence and explain why import precedes start:

```text
import("sample_typekit")
loadComponent("sample", "SampleComponent")
opcua.start()
opcua.publishComponent("sample")
```

Document that `endpointUrl()` is configuration, `isRunning()` is listener plus
complete Deployer publication, `ctaskbrowser-opcua` cannot connect before
start, publication is strict/static/idempotent, `Server=true` is ignored for
OPC UA, and published components cannot be unloaded in this version.

Update `rtt_opcua/README.md` to use `publishComponent` and state that model
destruction is endpoint teardown, not public unpublish. Mark conflicting
dynamic-lifetime portions of the older custom-datatype design as superseded by
`opcua-deployer-lifecycle-design.md`; do not rewrite unrelated historical
decisions.

Remove claims that patched dependency forks or dependency unit-test totals are
part of current evidence. Reserve the package-results table for the fresh Task
8 results; do not carry forward old pass counts.

- [ ] **Step 4: Check docs, policy, and stale API names**

```bash
ruby tools/check-package-tests-ci.rb
ruby tools/check-autoproj-policy.rb
rg -n 'publishPeer|unpublishPeer|reconcile_interval|maintenance fork|patched open62541' \
  README.md docs/src toolchain/tools/rtt_opcua/README.md \
  --glob '!opcua-deployer-lifecycle-plan.md'
mdbook build docs --dest-dir "$OROCOS_OPCUA_VERIFY_ROOT/mdbook"
git diff --check
```

Expected: checkers and mdBook pass. Any remaining historical term is either
removed or explicitly labeled superseded rather than presented as current
behavior.

- [ ] **Step 5: Commit package-local and root documentation**

```bash
git -C toolchain/tools/rtt_opcua add README.md
git -C toolchain/tools/rtt_opcua commit -m \
  "docs: describe static OPC UA publication"

git add tools/check-package-tests-ci.rb tools/test-package.sh \
  docs/src/user-guide.md docs/src/opcua-custom-datatype-verification.md \
  docs/src/package-test-results.md \
  docs/src/orocos-opcua-custom-datatype-design.md
git commit -m "docs: align OPC UA lifecycle verification"
```

If OCL documentation changed, include it in a separate OCL documentation
commit. Do not stage unrelated root documentation.

---

## Task 8: Verify, Review, And Prepare Default-Branch Integration

**Files:**

- Modify after tests: `docs/src/package-test-results.md`
- Modify after tests: `docs/src/opcua-custom-datatype-verification.md`
- No third-party source files

**Consumes:** committed Tasks 1 through 7 and the approved lifecycle design.

**Produces:** reproducible evidence from unmodified stock dependencies,
warning-clean maintained builds, sanitizer runs, manual TaskBrowser validation,
and a package commit summary suitable for user approval before merging.

- [ ] **Step 1: Audit source revisions before building**

```bash
git status --short --branch
git -C toolchain/tools/rtt_opcua status --short --branch
git -C toolchain/tools/ocl status --short --branch
git -C toolchain/open62541 rev-parse v1.4.15^{commit}
git -C toolchain/open62541pp rev-parse v0.21.2^{commit}
git diff --check
git -C toolchain/tools/rtt_opcua diff --check
git -C toolchain/tools/ocl diff --check
```

Expected tag commits are open62541
`45e4cd3ef6c79a8e503d37c9f5c89fefe90d99db` and open62541pp
`b1696768b26a12d0f40fdac5ec62ad78d25fa236`. Stop if maintained package
changes are uncommitted except for the user's explicitly preserved unrelated
root documentation changes.

- [ ] **Step 2: Build stock dependencies into the isolated prefix**

Create detached clean source worktrees below the verification root at the
exact tags; do not use the dirty experimental dependency worktrees:

```bash
mkdir -p "$OROCOS_OPCUA_VERIFY_ROOT/src" \
  "$OROCOS_OPCUA_VERIFY_ROOT/build"
git -C toolchain/open62541 worktree add --detach \
  "$OROCOS_OPCUA_VERIFY_ROOT/src/open62541" v1.4.15
git -C toolchain/open62541pp worktree add --detach \
  "$OROCOS_OPCUA_VERIFY_ROOT/src/open62541pp" v0.21.2
```

Clone the selected farbot and rtlog-cpp branches into the same temporary source
root, record their resolved commits, and build them before the OPC UA
dependencies:

```bash
git clone --branch master --single-branch \
  https://github.com/liufang-robot/farbot.git \
  "$OROCOS_OPCUA_VERIFY_ROOT/src/farbot"
git clone --branch main --single-branch \
  https://github.com/liufang-robot/rtlog-cpp.git \
  "$OROCOS_OPCUA_VERIFY_ROOT/src/rtlog-cpp"

cmake -S "$OROCOS_OPCUA_VERIFY_ROOT/src/farbot" \
  -B "$OROCOS_OPCUA_VERIFY_ROOT/build/farbot" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$OROCOS_OPCUA_DEPENDENCY_PREFIX"
cmake --build "$OROCOS_OPCUA_VERIFY_ROOT/build/farbot" --parallel \
  --target install

cmake -S "$OROCOS_OPCUA_VERIFY_ROOT/src/rtlog-cpp" \
  -B "$OROCOS_OPCUA_VERIFY_ROOT/build/rtlog-cpp" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  -DCMAKE_PREFIX_PATH="$OROCOS_OPCUA_DEPENDENCY_PREFIX"
cmake --build "$OROCOS_OPCUA_VERIFY_ROOT/build/rtlog-cpp" --parallel \
  --target install
```

Configure the detached dependencies with:

```text
open62541:
  BUILD_SHARED_LIBS=ON
  UA_NAMESPACE_ZERO=REDUCED
  UA_ENABLE_PUBSUB=OFF
  UA_BUILD_EXAMPLES=OFF
  UA_BUILD_UNIT_TESTS=OFF

open62541pp:
  BUILD_SHARED_LIBS=ON
  UAPP_INTERNAL_OPEN62541=OFF
  UAPP_BUILD_TESTS=OFF
  UAPP_BUILD_EXAMPLES=OFF
  UAPP_BUILD_DOCUMENTATION=OFF
```

Use `CMAKE_INSTALL_PREFIX=$OROCOS_OPCUA_DEPENDENCY_PREFIX` and build/install
ordinary library targets only. Capture configure output proving both test
options are off. The complete commands are:

```bash
cmake -S "$OROCOS_OPCUA_VERIFY_ROOT/src/open62541" \
  -B "$OROCOS_OPCUA_VERIFY_ROOT/build/open62541" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  -DBUILD_SHARED_LIBS=ON -DUA_NAMESPACE_ZERO=REDUCED \
  -DUA_ENABLE_PUBSUB=OFF -DUA_ENABLE_PUBSUB_INFORMATIONMODEL=OFF \
  -DUA_BUILD_EXAMPLES=OFF -DUA_BUILD_UNIT_TESTS=OFF
cmake --build "$OROCOS_OPCUA_VERIFY_ROOT/build/open62541" --parallel \
  --target install

cmake -S "$OROCOS_OPCUA_VERIFY_ROOT/src/open62541pp" \
  -B "$OROCOS_OPCUA_VERIFY_ROOT/build/open62541pp" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  -DCMAKE_PREFIX_PATH="$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  -DBUILD_SHARED_LIBS=ON -DUAPP_INTERNAL_OPEN62541=OFF \
  -DUAPP_BUILD_TESTS=OFF -DUAPP_BUILD_EXAMPLES=OFF \
  -DUAPP_BUILD_DOCUMENTATION=OFF
cmake --build "$OROCOS_OPCUA_VERIFY_ROOT/build/open62541pp" --parallel \
  --target install
```

Do not invoke either dependency's CTest suite.

- [ ] **Step 3: Run clean installed-prefix maintained acceptance**

Use a new empty prefix distinct from the dependency prefix:

```bash
MAINTAINED_PREFIX="$(mktemp -d /tmp/orocos-opcua-maintained.XXXXXX)"
HOME="$OROCOS_OPCUA_TEST_HOME" \
  ./tools/test-opcua-custom-datatypes.sh \
    --prefix "$MAINTAINED_PREFIX" \
    --dependency-prefix "$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
    --target gnulinux
```

Expected: C++20 warning-clean RTT, `rtt_opcua`, OCL, executable, and fixture
builds pass, along with all maintained package tests and both automated
Deployer endpoint states. Confirm `$OROCOS_OPCUA_TEST_HOME/.orocos` was not
created and no configured prefix refers to the real home `.orocos`.

- [ ] **Step 4: Run sanitizer builds for owned code**

Configure fresh Debug `rtt_opcua` and OCL build trees below
`$OROCOS_OPCUA_VERIFY_ROOT/sanitizers` with:

```text
-fsanitize=address,undefined
-fno-omit-frame-pointer
```

Link against the temporary RTT/dependency installation, enable maintained
tests, and retain warning-as-error options. Configure, build, and run with:

```bash
SANITIZER_FLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer'

cmake -S toolchain/tools/rtt_opcua \
  -B "$OROCOS_OPCUA_VERIFY_ROOT/sanitizers/rtt-opcua" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_PREFIX_PATH="$MAINTAINED_PREFIX;$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$SANITIZER_FLAGS" \
  -DBUILD_TESTING=ON -DRTT_OPCUA_WARNINGS_AS_ERRORS=ON
cmake --build "$OROCOS_OPCUA_VERIFY_ROOT/sanitizers/rtt-opcua" --parallel

ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
ctest --test-dir "$OROCOS_OPCUA_VERIFY_ROOT/sanitizers/rtt-opcua" \
  --output-on-failure -R '^rtt_opcua_.*_test$'

cmake -S toolchain/tools/ocl \
  -B "$OROCOS_OPCUA_VERIFY_ROOT/sanitizers/ocl" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_PREFIX_PATH="$MAINTAINED_PREFIX;$OROCOS_OPCUA_DEPENDENCY_PREFIX" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$SANITIZER_FLAGS" \
  -DBUILD_TESTING=ON -DBUILD_TESTS=ON -DBUILD_DEPLOYMENT=ON \
  -DBUILD_TASKBROWSER=ON -DBUILD_OPCUA=ON
cmake --build "$OROCOS_OPCUA_VERIFY_ROOT/sanitizers/ocl" --parallel \
  --target ocl_opcua_deployment_test

ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
ctest --test-dir "$OROCOS_OPCUA_VERIFY_ROOT/sanitizers/ocl" \
  --output-on-failure -R '^ocl_opcua_deployment_.*$'
```

The immediate-shutdown-after-`BadTimeout` case must execute in this run.
Treat sanitizer errors, leaks in owned callback state, hangs, or skipped
lifetime cases as failures. Do not build dependency tests to investigate an
owned-code failure.

- [ ] **Step 5: Perform the manual TaskBrowser acceptance**

Source only the runtime environment emitted by the successful root harness.
In terminal A, run the installed `deployer-opcua` with the installed start
script and a fresh loopback port. In its local browser, confirm:

```text
opcua.isRunning()
opcua.endpointUrl()
opcua.publishComponent("sample")
```

In terminal B, connect the installed browser directly to the sample, importing
its local typekit/transport first:

```bash
ctaskbrowser-opcua --import orocos_opcua_fixture \
  "$ENDPOINT_URL" sample
```

At the `sample` prompt, verify:

```text
Gain = 9
Status = "running"
echo(42)
```

Read the values back. Confirm the constant remains read-only, supported
attribute/property writes work, both Deployer and sample browse completely,
and the unsupported component is absent after its strict publication failure.
Terminate the deployer cleanly and record the commands and observations.

- [ ] **Step 6: Run final policy, docs, and stale-surface checks**

```bash
ruby tools/check-autoproj-policy.rb
ruby tools/check-package-tests-ci.rb
ruby tools/check-cpp20-policy.rb
mdbook build docs --dest-dir "$OROCOS_OPCUA_VERIFY_ROOT/final-book"
rg -n 'ComponentRegistration|registerComponent|reconcile_interval|publishPeer|unpublishPeer|unpublishComponent' \
  toolchain/tools/rtt_opcua/include toolchain/tools/rtt_opcua/src \
  toolchain/tools/ocl/deployment toolchain/tools/ocl/bin \
  tests/opcua-custom-datatypes
git diff --check
git -C toolchain/tools/rtt_opcua diff --check
git -C toolchain/tools/ocl diff --check
```

Expected: all checks pass and `rg` returns no production matches.

- [ ] **Step 7: Record fresh evidence and commit it**

Update both evidence documents with:

- exact root, RTT, `rtt_opcua`, OCL, open62541, and open62541pp commit IDs;
- concrete temporary prefixes;
- compiler and CMake versions;
- configure flags proving dependency tests were off;
- maintained CTest case counts and sanitizer results;
- standalone and Deployer fixture results;
- manual `ctaskbrowser-opcua` observations; and
- the accepted non-returning-operation shutdown limitation.

Do not report dependency unit-test pass counts because those tests were not
built.

```bash
git add docs/src/package-test-results.md \
  docs/src/opcua-custom-datatype-verification.md
git commit -m "docs: record static OPC UA verification"
```

- [ ] **Step 8: Review every package before integration**

```bash
git log --oneline --decorate liufang/main..HEAD
git -C toolchain/tools/rtt_opcua log --oneline --decorate liufang/dev..HEAD
git -C toolchain/tools/ocl log --oneline --decorate liufang/dev..HEAD
git diff --stat liufang/main...HEAD
git -C toolchain/tools/rtt_opcua diff --stat liufang/dev...HEAD
git -C toolchain/tools/ocl diff --stat liufang/dev...HEAD
git status --short --branch
git -C toolchain/tools/rtt_opcua status --short --branch
git -C toolchain/tools/ocl status --short --branch
```

Summarize for the user:

- commits and behavior by owning repository;
- source pins and first-party upstream branches;
- test/sanitizer/manual evidence;
- preserved unrelated changes;
- deferred unpublish/unload-after-publication/security scope; and
- any remaining Xenomai-only validation for the other machine.

Wait for explicit approval before merging the feature histories into their
default branches and pushing those default branches to `liufang-robot`.
