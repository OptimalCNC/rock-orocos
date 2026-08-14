# Native RTT Task State Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or
> `superpowers:executing-plans` to implement this plan task-by-task. Every
> production change follows a witnessed RED, minimal GREEN, and regression
> pass.

**Goal:** Replace the synthetic OPC UA `lifecycleState` String Variable with
native RTT `getTaskState` and `getTargetState` operations transported by the
generic OPC UA operation mapper.

**Architecture:** RTT registers the existing `TaskCore::TaskState` as the
canonical RTT type `TaskState` and exposes both existing state getters as
component-root `ClientThread` operations. `rtt_opcua` binds `TaskState` to a
strict scalar OPC UA `Int32` codec, publishes the getters through its ordinary
operation snapshot, and invokes the same operations from `TaskContextProxy`.
The proxy uses the existing Boolean lifecycle operations for predicates and
uses `getTaskState` only as a liveness call in `ready()`. OCL remains a generic
consumer and adds end-to-end acceptance coverage only.

**Tech Stack:** C++20, Orocos RTT 2.10, `rtt_opcua`, open62541pp 0.21.2,
Boost.Test, OCL, CMake/CTest, mdBook, TaskBrowser, and the retained temporary
interface probe.

## Global Constraints

- Implement the approved contract in
  `opcua-native-task-state-operations-design.md` without adding selector,
  permission, SDK, or application semantics.
- Keep the existing `TaskCore::TaskState` enum definition and numeric values
  unchanged: `Init=0`, `PreOperational=1`, `FatalError=2`, `Exception=3`,
  `Stopped=4`, `Running=5`, and `RunTimeError=6`.
- Register the RTT name exactly as `TaskState`. Never expose `unknown_t` and do
  not add global scripting constants for state names.
- Register `getTaskState` and `getTargetState` on every ordinary TaskContext
  root service with `ClientThread`; do not add lifecycle-specific transport
  callbacks.
- Encode and decode `TaskState` only as exact scalar built-in OPC UA `Int32`.
  Reject strings, arrays, other numeric widths, and codes outside `0..6`.
- Remove `lifecycleState` completely. Do not dual-publish it and do not add a
  compatibility fallback in the proxy.
- Require proxy synchronization to discover valid root schemas for both state
  getters and the six native Boolean lifecycle predicates.
- Implement `isConfigured`, `isActive`, `isRunning`, `inFatalError`,
  `inException`, and `inRunTimeError` by calling their same-named Boolean
  operations. Do not infer them from enum ordering.
- On a failed state call, incompatible result, or invalid state code, mark the
  proxy interface stale, retain a useful diagnostic, and return `Init`.
- Keep OCL production code unchanged. Its deployment test and the temporary
  probe consume the generic mapping.
- Install RTT before configuring `rtt_opcua`, then install `rtt_opcua` before
  configuring OCL. Put the feature build/install libraries before the base
  prefix in every loader path.
- Never stage `build/`, `install/`, `orocos.log`, `.tb_history`, or temporary
  probe output.

## Workspace

Use these paths throughout:

```bash
feature_root=/home/liufang/MetaNC/rock-orocos/.worktrees/opcua-native-task-state-plan
feature_prefix="$feature_root/install"
base_prefix=/home/liufang/.orocos/toolchain
probe_root=/tmp/rtt-opcua-interface-probe.7Ym4Ma
export OROCOS_TARGET=gnulinux
```

The linked feature branches are:

```text
root:       codex/opcua-native-task-state-plan
RTT:        codex/opcua-native-task-state-operations
rtt_opcua:  codex/opcua-native-task-state-operations
OCL:        codex/opcua-native-task-state-operations
```

---

### Task 1: Register And Export Native RTT State Operations

**Files:**

- Modify: `toolchain/tools/rtt/tests/typekit_test.cpp`
- Modify: `toolchain/tools/rtt/tests/taskstates_test.cpp`
- Modify: `toolchain/tools/rtt/rtt/typekit/RealTimeTypekitTypes2.cpp`
- Modify: `toolchain/tools/rtt/rtt/TaskContext.cpp`

**Interfaces:**

- Produces RTT TypeInfo `TaskState` for
  `RTT::base::TaskCore::TaskState` using `EnumTypeInfo` without string labels.
- Produces component-root operations `getTaskState() -> TaskState` and
  `getTargetState() -> TaskState` with `ClientThread` policy.
- Preserves the existing C++ enum definition and all lifecycle transition
  implementation.

- [ ] **Step 1: Add the failing typekit contract test**

  Extend `testCanonicalBuiltinTypesAreRegistered` to require `TaskState` and
  require that `Types()->getTypeInfo<RTT::base::TaskCore::TaskState>()` resolves
  to the exact canonical name `TaskState`. Add literal assertions for all seven
  existing numeric codes.

  The production mutation caught by this test is removing or renaming the
  TaskState TypeInfo registration.

- [ ] **Step 2: Add failing native-operation behavior tests**

  In `taskstates_test.cpp`, add a test that obtains typed operation callers
  from a normal `TaskContext` root:

  ```cpp
  OperationCaller<TaskContext::TaskState(void)> current =
      tc->getOperation("getTaskState");
  OperationCaller<TaskContext::TaskState(void)> target =
      tc->getOperation("getTargetState");
  ```

  Require both callers to be ready, require their return TypeInfo to be named
  `TaskState`, call them before and after a transition, and prove the calls do
  not alter component state.

  Add a small test TaskContext whose `startHook()` invokes both operation
  callers and records their results. After `start()`, require the values
  observed inside the hook to be `Stopped` for current state and `Running` for
  target state. This catches accidentally wiring both operations to the same
  getter.

- [ ] **Step 3: Configure and witness RED**

  ```bash
  cmake -S "$feature_root/toolchain/tools/rtt" \
    -B "$feature_root/toolchain/tools/rtt/build" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX="$feature_prefix" \
    -DOROCOS_TARGET=gnulinux \
    -DENABLE_TESTS=ON \
    -DBUILD_TESTING=ON \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  cmake --build "$feature_root/toolchain/tools/rtt/build" --parallel 2 \
    --target typekit_test taskstates_test
  ctest --test-dir "$feature_root/toolchain/tools/rtt/build" \
    --output-on-failure -R '^(typekit_test|taskstates_test)$'
  ```

  Expected RED: `TaskState` is absent and the two root operation callers are
  not ready. Compilation itself must succeed.

- [ ] **Step 4: Add the minimal RTT registration and operations**

  In `RealTimeTypekitTypes2.cpp`, include `base/TaskCore.hpp` and
  `types/EnumTypeInfo.hpp`, then register:

  ```cpp
  ti->addType(
      new EnumTypeInfo<base::TaskCore::TaskState>("TaskState"));
  ```

  Do not call an enum-name registration API and do not populate state-name
  constants.

  In `TaskContext::setup()`, add:

  ```cpp
  this->addOperation("getTaskState", &TaskContext::getTaskState, this,
                     ClientThread)
      .doc("Get the current TaskContext lifecycle state.");
  this->addOperation("getTargetState", &TaskContext::getTargetState, this,
                     ClientThread)
      .doc("Get the target TaskContext lifecycle state.");
  ```

- [ ] **Step 5: Verify GREEN, full RTT regression, and install**

  ```bash
  cmake --build "$feature_root/toolchain/tools/rtt/build" --parallel 2
  ctest --test-dir "$feature_root/toolchain/tools/rtt/build" \
    --output-on-failure -R '^(typekit_test|taskstates_test)$'
  ctest --test-dir "$feature_root/toolchain/tools/rtt/build" \
    --output-on-failure --timeout 150
  cmake --install "$feature_root/toolchain/tools/rtt/build"
  git -C "$feature_root/toolchain/tools/rtt" diff --check
  ```

  Expected: focused and complete configured RTT suites pass; the installed
  typekit and headers come from the feature prefix.

- [ ] **Step 6: Commit RTT**

  ```bash
  git -C "$feature_root/toolchain/tools/rtt" add \
    rtt/TaskContext.cpp rtt/typekit/RealTimeTypekitTypes2.cpp \
    tests/taskstates_test.cpp tests/typekit_test.cpp
  git -C "$feature_root/toolchain/tools/rtt" commit \
    -m "feat: expose native task state operations"
  ```

---

### Task 2: Add The Strict TaskState OPC UA Codec

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/type_descriptor.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/type_protocol.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/type_protocol_test.cpp`

**Interfaces:**

- Adds canonical descriptor `TaskState -> Int32`, scalar, with values.
- Adds a protocol bound to `RTT::base::TaskCore::TaskState` whose codec rejects
  every value outside `0..6` on encode, assignment, proxy refresh, and port
  access.
- Keeps operation metadata type name `TaskState` while using OPC UA built-in
  `Int32` on the wire.

- [ ] **Step 1: Add failing codec tests**

  Add a table of the seven literal enum/code pairs. For each pair, require
  `toVariant`, `makeDataSource`, and `assignVariant` to round-trip exact scalar
  `Int32`. Require the codec's datatype and rank to be built-in `Int32` and
  scalar.

  Add negative cases for `-1`, `7`, String, `UInt32`, and an `Int32` array.
  Also construct invalid local enum values with `static_cast<TaskState>(-1)`
  and `static_cast<TaskState>(7)` and require encoding to fail. These catch an
  unrestricted `static_cast` implementation in either direction.

- [ ] **Step 2: Configure against feature RTT and witness RED**

  ```bash
  export PKG_CONFIG_PATH="$feature_prefix/lib/pkgconfig:$base_prefix/lib/pkgconfig"
  cmake -S "$feature_root/toolchain/tools/rtt_opcua" \
    -B "$feature_root/toolchain/tools/rtt_opcua/build" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_PREFIX_PATH="$feature_prefix;$base_prefix" \
    -DCMAKE_INSTALL_PREFIX="$feature_prefix" \
    -DBUILD_TESTING=ON \
    -DRTT_OPCUA_WARNINGS_AS_ERRORS=ON \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2 \
    --target rtt_opcua_type_protocol_test
  LD_LIBRARY_PATH="$feature_root/toolchain/tools/rtt/build/rtt:$feature_prefix/lib:$base_prefix/lib" \
    ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
      --output-on-failure -R '^rtt_opcua_type_protocol_test$'
  ```

  Expected RED: no canonical `TaskState` codec exists.

- [ ] **Step 3: Implement bounded scalar conversion**

  Add `TaskState` to `canonicalTypeDescriptors()` as built-in `Int32`.
  Include `rtt/base/TaskCore.hpp` in `type_protocol.cpp` and add one shared
  validity predicate:

  ```cpp
  bool isValidTaskState(RTT::base::TaskCore::TaskState state) noexcept;
  ```

  Make the TaskState scalar protocol validate both the typed enum before
  encoding and the `std::int32_t` code before conversion. Reuse this validation
  in `toVariant`, `assignVariant`, `makeDataSource`, proxy data-source refresh
  and assignment, and `portValue`. Do not weaken exact Variant type/rank checks
  for any scalar codec.

  Register the protocol branch as:

  ```cpp
  ScalarTypeProtocol<RTT::base::TaskCore::TaskState, std::int32_t>
  ```

  with the bounded validation policy, not the unrestricted status-enum cast.

- [ ] **Step 4: Verify GREEN, install, and commit**

  ```bash
  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2 \
    --target rtt_opcua_type_protocol_test
  LD_LIBRARY_PATH="$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/toolchain/tools/rtt/build/rtt:$feature_prefix/lib:$base_prefix/lib" \
    ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
      --output-on-failure -R '^rtt_opcua_type_protocol_test$'
  cmake --install "$feature_root/toolchain/tools/rtt_opcua/build"
  git -C "$feature_root/toolchain/tools/rtt_opcua" diff --check
  git -C "$feature_root/toolchain/tools/rtt_opcua" add \
    src/type_descriptor.cpp src/type_protocol.cpp tests/type_protocol_test.cpp
  git -C "$feature_root/toolchain/tools/rtt_opcua" commit \
    -m "feat: transport RTT task state as Int32"
  ```

---

### Task 3: Publish Only Native State Methods

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`

**Interfaces:**

- Removes the `LifecycleDataSource`, `lifecycleSpec`, state-name formatter, and
  synthetic snapshot insertion.
- Relies exclusively on the existing `OperationDispatcher` and operation
  metadata nodes for both state getters.

- [ ] **Step 1: Add failing address-space tests**

  In the complete snapshot test, replace the String lifecycle assertion with:

  - `lifecycleState` returns `BadNodeIdUnknown`;
  - both getter Method nodes exist under the root `operations` folder;
  - each has no inputs and one scalar built-in `Int32` result;
  - each `rttOutputTypes` metadata property is exactly `{"TaskState"}`;
  - direct calls return the component's literal current and target numeric
    codes.

  This catches either retaining the synthetic Variable or bypassing the
  generic method schema.

- [ ] **Step 2: Witness RED**

  ```bash
  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2 \
    --target rtt_opcua_object_model_test
  LD_LIBRARY_PATH="$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/toolchain/tools/rtt/build/rtt:$feature_prefix/lib:$base_prefix/lib" \
    ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
      --output-on-failure -R '^rtt_opcua_object_model_test$'
  ```

  Expected RED: `lifecycleState` still exists before the production deletion.
  If Task 1 and Task 2 are installed correctly, both native methods already
  publish through the generic mapper.

- [ ] **Step 3: Remove only synthetic lifecycle publication**

  Delete `taskStateName`, `LifecycleDataSource`, `lifecycleSpec`, and the
  `insertNode(... lifecycleSpec(...))` call from `snapshotComponent`. Do not
  add replacement node code or modify `OperationDispatcher`.

- [ ] **Step 4: Verify GREEN and commit**

  ```bash
  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2 \
    --target rtt_opcua_object_model_test
  LD_LIBRARY_PATH="$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/toolchain/tools/rtt/build/rtt:$feature_prefix/lib:$base_prefix/lib" \
    ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
      --output-on-failure -R '^rtt_opcua_object_model_test$'
  git -C "$feature_root/toolchain/tools/rtt_opcua" diff --check
  git -C "$feature_root/toolchain/tools/rtt_opcua" add \
    src/object_model.cpp tests/object_model_test.cpp
  git -C "$feature_root/toolchain/tools/rtt_opcua" commit \
    -m "feat: publish native task state methods"
  ```

---

### Task 4: Make TaskContextProxy Use Native Lifecycle Operations

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/client_session.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/client_session.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/task_context_proxy.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`

**Interfaces:**

- Removes `ClientSession::readLifecycleState` and String state parsing.
- Requires exact root schemas for `getTaskState`, `getTargetState`, and the six
  Boolean predicate operations during synchronization.
- Adds a dedicated state-operation invocation path that validates exactly one
  scalar built-in `Int32` result in `0..6`.

- [ ] **Step 1: Add failing proxy behavior tests**

  Add real published TaskContexts that expose deliberately divergent virtual
  state getters and predicate results. Require:

  - proxy `getTaskState()` and `getTargetState()` return different literal
    values matching the remote virtual methods;
  - all six predicates match their same-named remote Boolean operation even
    when those results disagree with enum ordering;
  - deleting `getTargetState` before proxy creation makes synchronization fail;
  - replacing a required method with an incompatible result schema makes
    synchronization fail;
  - replacing the `getTaskState` method callback while preserving its schema
    so it returns `Int32(7)` causes `getTaskState()` to return `Init`, mark the
    interface stale, and report both the operation name and code;
  - stopping the server makes `ready()` false and marks the interface stale.

  Use the real open62541pp server and `setMethodCallback`; do not assert on a
  mock.

- [ ] **Step 2: Witness RED**

  ```bash
  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2 \
    --target rtt_opcua_task_context_proxy_test
  LD_LIBRARY_PATH="$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/toolchain/tools/rtt/build/rtt:$feature_prefix/lib:$base_prefix/lib" \
    ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
      --output-on-failure -R '^rtt_opcua_task_context_proxy_test$'
  ```

  Expected RED: target state aliases current state, predicates are inferred,
  missing getters do not fail synchronization, and the proxy still reads the
  removed String Variable.

- [ ] **Step 3: Validate required root operation schemas**

  Validate discovered root `RemoteOperationDescription` entries before
  installing the staged interface. Require zero inputs, one return output from
  source `-1`, and exact RTT output type:

  ```text
  getTaskState       TaskState
  getTargetState     TaskState
  isConfigured       Bool
  isActive           Bool
  isRunning          Bool
  inFatalError       Bool
  inException        Bool
  inRunTimeError     Bool
  ```

  Report the missing or incompatible operation name in the synchronization
  error. Nested services are unaffected.

- [ ] **Step 4: Replace String reads with strict method invocation**

  Delete `readLifecycleState`, `parseTaskState`, and `readTaskState`. Add an
  `Impl::invokeTaskStateOperation(std::string_view)` path that shares the
  existing ready/stale lock discipline, calls `ClientSession::callOperation`,
  requires exactly one exact scalar Int32 output, checks `0..6`, clears the
  control error on success, and otherwise calls `markInterfaceStale` before
  returning `Init`.

  Implement:

  ```cpp
  getTaskState()   -> invokeTaskStateOperation("getTaskState")
  getTargetState() -> invokeTaskStateOperation("getTargetState")
  ```

  Change all six predicates to `invokeOperation<bool>(same_name, false)`.
  Keep `ready()` as a synchronized/connected check followed by a
  `getTaskState` liveness call; judge readiness from connection/interface
  freshness, not from the returned enum value.

- [ ] **Step 5: Verify focused and complete rtt_opcua suites**

  ```bash
  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2
  LD_LIBRARY_PATH="$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/toolchain/tools/rtt/build/rtt:$feature_prefix/lib:$base_prefix/lib" \
    ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
      --output-on-failure -R '^rtt_opcua_.*_test$'
  cmake --install "$feature_root/toolchain/tools/rtt_opcua/build"
  git -C "$feature_root/toolchain/tools/rtt_opcua" diff --check
  ```

- [ ] **Step 6: Commit proxy migration**

  ```bash
  git -C "$feature_root/toolchain/tools/rtt_opcua" add \
    src/client_session.hpp src/client_session.cpp src/task_context_proxy.cpp \
    tests/task_context_proxy_test.cpp
  git -C "$feature_root/toolchain/tools/rtt_opcua" commit \
    -m "feat: proxy native task state operations"
  ```

---

### Task 5: Prove The Coordinated OCL And Manual Deployer Contract

**Files:**

- Modify: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`
- Modify outside Git: `/tmp/rtt-opcua-interface-probe.7Ym4Ma/interface_probe_client.cpp`
- Modify outside Git: `/tmp/rtt-opcua-interface-probe.7Ym4Ma/taskbrowser.commands`
- Modify: `docs/src/opcua-native-task-state-operations-plan.md`

**Interfaces:**

- OCL remains a consumer of installed RTT and `rtt_opcua`; no deployment
  production source changes.
- The probe verifies the same address space through a deployer process, a
  direct OPC UA client, and TaskBrowser.

- [ ] **Step 1: Add failing OCL end-to-end assertions**

  Extend `strict_publication_is_static_and_idempotent` to require:

  - direct OPC UA calls to both getter Methods return scalar Int32 and the
    correct code;
  - the `rttOutputTypes` metadata remains `TaskState`;
  - `lifecycleState` is absent;
  - `TaskContextProxy` reports current and target state through the native
    operations and its Boolean predicates remain callable.

  Witness RED against the pre-migration OCL overlay before changing any OCL
  production source.

- [ ] **Step 2: Configure OCL against the feature overlay**

  ```bash
  export PKG_CONFIG_PATH="$feature_prefix/lib/pkgconfig:$base_prefix/lib/pkgconfig"
  cmake -S "$feature_root/toolchain/tools/ocl" \
    -B "$feature_root/toolchain/tools/ocl/build" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_PREFIX_PATH="$feature_prefix;$base_prefix" \
    -DCMAKE_INSTALL_PREFIX="$feature_prefix" \
    -DOROCOS_TARGET=gnulinux \
    -DBUILD_TESTING=ON \
    -DBUILD_TESTS=ON \
    -DBUILD_DEPLOYMENT=ON \
    -DBUILD_OPCUA=ON
  cmake --build "$feature_root/toolchain/tools/ocl/build" --parallel 2 \
    --target ocl_opcua_deployment_test deployer-opcua ctaskbrowser-opcua
  ```

- [ ] **Step 3: Verify OCL GREEN and commit only the test**

  ```bash
  LD_LIBRARY_PATH="$feature_root/toolchain/tools/ocl/build/deployment:$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/toolchain/tools/rtt/build/rtt:$feature_prefix/lib:$base_prefix/lib" \
    ctest --test-dir "$feature_root/toolchain/tools/ocl/build" \
      --output-on-failure -R '^ocl_opcua_deployment_.*$'
  cmake --install "$feature_root/toolchain/tools/ocl/build"
  git -C "$feature_root/toolchain/tools/ocl" diff --check
  git -C "$feature_root/toolchain/tools/ocl" add \
    deployment/tests/opcua_deployment_test.cpp
  git -C "$feature_root/toolchain/tools/ocl" commit \
    -m "test: verify native OPC UA task state methods"
  ```

- [ ] **Step 4: Rebuild and run the retained temporary probe**

  Update the direct client to call both state Methods, require exact scalar
  Int32 results and `TaskState` RTT metadata, and require `lifecycleState` to be
  missing. Add TaskBrowser commands for both operations.

  Reconfigure the probe with the feature prefix first, rebuild/install it, run
  `deployer-opcua probe.ops`, then run the direct client and
  `ctaskbrowser-opcua` command file. Capture logs below the probe directory.
  Confirm with `ldd` that deployer, client, and TaskBrowser resolve feature
  RTT, `rtt_opcua`, and OCL libraries before accepting results.

- [ ] **Step 5: Run final repository verification**

  ```bash
  ctest --test-dir "$feature_root/toolchain/tools/rtt/build" \
    --output-on-failure --timeout 150
  LD_LIBRARY_PATH="$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/toolchain/tools/rtt/build/rtt:$feature_prefix/lib:$base_prefix/lib" \
    ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
      --output-on-failure -R '^rtt_opcua_.*_test$'
  LD_LIBRARY_PATH="$feature_root/toolchain/tools/ocl/build/deployment:$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/toolchain/tools/rtt/build/rtt:$feature_prefix/lib:$base_prefix/lib" \
    ctest --test-dir "$feature_root/toolchain/tools/ocl/build" \
      --output-on-failure -R '^ocl_opcua_deployment_.*$'
  mdbook build "$feature_root/docs"
  mdbook test "$feature_root/docs"
  "$feature_root/tools/check-repository-policy.rb"
  git -C "$feature_root" diff --check
  git -C "$feature_root/toolchain/tools/rtt" diff --check
  git -C "$feature_root/toolchain/tools/rtt_opcua" diff --check
  git -C "$feature_root/toolchain/tools/ocl" diff --check
  ```

- [ ] **Step 6: Record evidence and commit root documentation**

  Update this chapter with the three nested commit IDs, exact test counts,
  probe/TaskBrowser outputs, library-resolution evidence, and clean-status
  results. Commit only the plan and SUMMARY entry:

  ```bash
  git -C "$feature_root" add \
    docs/src/SUMMARY.md \
    docs/src/opcua-native-task-state-operations-plan.md
  git -C "$feature_root" commit \
    -m "docs: record native task state verification"
  ```

## Mutation Checklist

- Removing either RTT operation fails RTT and address-space tests.
- Wiring `getTargetState` to `getTaskState` fails transition and divergent proxy
  tests.
- Renaming or omitting `TaskState` TypeInfo fails RTT and publication preflight.
- Encoding a String, another integer width, or an out-of-range code fails codec
  and proxy tests.
- Retaining `lifecycleState` fails direct address-space, OCL, and probe tests.
- Deriving any Boolean predicate from enum ordering fails the deliberately
  inconsistent remote predicate fixture.
- Treating `Init` as not ready fails the liveness semantics test; losing the
  server still makes `ready()` false.
