# OPC UA RTT Interface Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish and reconstruct every supported RTT operation, property,
attribute/constant, data port, generated port service, and nested service with
one generic OPC UA mapping, then prove the result through automated tests and
an application-neutral component under `/tmp`.

**Architecture:** `rtt_opcua` snapshots a `TaskContext` by recursively applying
one service-mapping function. A port has two independent views: a typed
sample-transfer object below `ports`, backed by an RTT anti-port, and its
ordinary RTT-generated adapter below `services`. OCL only owns endpoint
lifecycle and calls this mapper; the manual client invokes the OPC UA contract
directly and does not define an SDK API.

**Tech Stack:** C++20, Orocos RTT, OCL, open62541 `v1.4.15`, open62541pp
`v0.21.2`, Boost.Test, CMake/CTest, mdBook, OCL `.ops` scripts.

## Global Constraints

- Keep `rtt_opcua` and OCL independent of MetaNC types, names, and policy.
- Map the complete supported RTT interface before any future selector/filter.
- Keep publication static, strict, transactional, and lifetime-guarded.
- Treat `ports/<name>` as the sample data plane and `services/<name>` as the
  RTT-generated object plane; neither suppresses the other.
- Encode `FlowStatus` and `WriteStatus` as documented OPC UA `Int32` codes, not
  strings.
- Use the component input port's default `RTT::ConnPolicy` for OPC UA writes.
- Use the configured bounded lock-free queue only for collecting component
  output samples.
- Do not add SDK wrappers, application retry rules, selector grammar, access
  policy, dynamic reconciliation, or MetaNC dependencies.
- Keep the manual fixture untracked beneath a fresh `/tmp` directory and use
  canonical RTT built-in types only.

## File Structure

- `toolchain/tools/rtt_opcua/src/type_descriptor.cpp`: canonical RTT type to
  OPC UA datatype catalog.
- `toolchain/tools/rtt_opcua/src/type_protocol.cpp`: generic enum/scalar codec
  registration for RTT status values.
- `toolchain/tools/rtt_opcua/src/port_bridge.cpp`: anti-port construction,
  direction-specific connection policy, and sample/status conversion.
- `toolchain/tools/rtt_opcua/src/object_model.cpp`: deterministic data-port
  nodes and recursive service snapshot.
- `toolchain/tools/rtt_opcua/src/client_session.cpp`: remote schema validation.
- `toolchain/tools/rtt_opcua/src/remote_port.cpp`: proxy data-plane pumping.
- `toolchain/tools/rtt_opcua/src/task_context_proxy.cpp`: simultaneous local
  installation of same-named ports and services.
- `toolchain/tools/rtt_opcua/tests/type_protocol_test.cpp`: status codec tests.
- `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`: server mapping and
  direct OPC UA behavior tests.
- `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`: reconstructed
  RTT interface and end-to-end port/service tests.
- `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`: deployer
  publication integration test.
- `docs/src/opcua-rtt-interface-mapping-design.md`: approved mapping contract.
- `/tmp/rtt-opcua-interface-probe.<unique>/`: untracked component, client,
  deployer script, build tree, installed overlay, logs, and evidence.

---

### Task 1: Canonical RTT Status Codecs

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/type_descriptor.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/type_protocol.cpp`
- Test: `toolchain/tools/rtt_opcua/tests/foundation_test.cpp`
- Test: `toolchain/tools/rtt_opcua/tests/type_protocol_test.cpp`

**Interfaces:**

- Consumes: RTT `FlowStatus` and `WriteStatus` from `rtt/FlowStatus.hpp`.
- Produces: `EndpointTypeRegistry::codecForTypeName("FlowStatus")` and
  `codecForTypeName("WriteStatus")`, both scalar OPC UA `Int32` codecs.
- Produces: the fixed values `NoData=0`, `OldData=1`, `NewData=2`,
  `WriteSuccess=0`, `WriteFailure=1`, and `NotConnected=2`.

- [ ] **Step 1: Extend the exact canonical-catalog test and add status
  round-trip tests**

  Update `canonical_builtin_catalog_is_exact` to include `FlowStatus` and
  `WriteStatus`. Add a focused test that encodes and decodes every status via
  `TypeCodec`, including rejection of a String variant:

  ```cpp
  BOOST_AUTO_TEST_CASE(status_protocols_use_documented_int32_codes) {
    const auto registry = makeRegistry();
    const auto *flow = registry->codecForTypeName("FlowStatus");
    const auto *write = registry->codecForTypeName("WriteStatus");
    BOOST_REQUIRE(flow != nullptr);
    BOOST_REQUIRE(write != nullptr);

    RTT::internal::ValueDataSource<RTT::FlowStatus>::shared_ptr new_data =
        new RTT::internal::ValueDataSource<RTT::FlowStatus>(RTT::NewData);
    ::opcua::Variant encoded;
    BOOST_REQUIRE(flow->toVariant(new_data, &encoded));
    BOOST_TEST(encoded.to<std::int32_t>() == 2);

    const auto disconnected =
        write->makeDataSource(::opcua::Variant(std::int32_t{2}));
    const auto typed = boost::dynamic_pointer_cast<
        RTT::internal::DataSource<RTT::WriteStatus>>(disconnected);
    BOOST_REQUIRE(typed);
    BOOST_TEST(typed->get() == RTT::NotConnected);
    BOOST_TEST(!flow->makeDataSource(::opcua::Variant(std::string("NewData"))));
  }
  ```

- [ ] **Step 2: Run the focused tests and verify the red state**

  Run:

  ```bash
  cmake --build toolchain/tools/rtt_opcua/build --parallel 2 \
    --target rtt_opcua_foundation_test rtt_opcua_type_protocol_test
  ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
    -R '^(rtt_opcua_foundation_test|rtt_opcua_type_protocol_test)$'
  ```

  Expected: the catalog and status-codec assertions fail because neither RTT
  status type has a registered OPC UA protocol.

- [ ] **Step 3: Register both enum concepts through the scalar codec path**

  Add descriptors mapping both names to `DataTypeId::Int32`, include
  `rtt/FlowStatus.hpp`, and add these exact protocol branches:

  ```cpp
  if (type_name == "FlowStatus") {
    return std::make_unique<
        ScalarTypeProtocol<RTT::FlowStatus, std::int32_t>>(
        descriptor->data_type, fingerprint);
  }
  if (type_name == "WriteStatus") {
    return std::make_unique<
        ScalarTypeProtocol<RTT::WriteStatus, std::int32_t>>(
        descriptor->data_type, fingerprint);
  }
  ```

  Keep the generic `encodeScalar`/`decodeScalarValue` conversions as the only
  implementation of the numeric mapping.

- [ ] **Step 4: Run the focused tests and verify the green state**

  Run the Step 2 commands again. Expected: both executables build with warning
  gates enabled and both CTest cases pass.

- [ ] **Step 5: Commit the status codec change in `rtt_opcua`**

  ```bash
  git -C toolchain/tools/rtt_opcua add \
    src/type_descriptor.cpp src/type_protocol.cpp \
    tests/foundation_test.cpp tests/type_protocol_test.cpp
  git -C toolchain/tools/rtt_opcua commit \
    -m "feat: map RTT port statuses as Int32"
  ```

### Task 2: Direction-Correct Port Data Plane

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/port_bridge.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/client_session.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/remote_port.cpp`
- Test: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`
- Test: `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`

**Interfaces:**

- Consumes: sample codecs plus the Task 1 `FlowStatus` and `WriteStatus`
  codecs.
- Produces: input-port method `write(value: T) -> status: Int32`.
- Produces: output-port method `read() -> (status: Int32, value: T)`.
- Produces: `PortBridge::create` behavior that uses the published input's
  default policy for input/event-input writes and `port_buffer_size` only for
  published output collection.

- [ ] **Step 1: Change direct-server tests to assert typed statuses and input
  default-policy behavior**

  Replace string assertions with numeric ones:

  ```cpp
  BOOST_TEST(empty_feedback_result.outputArguments()[0].to<std::int32_t>() ==
             static_cast<std::int32_t>(RTT::NoData));
  BOOST_TEST(command_result.outputArguments()[0].to<std::int32_t>() ==
             static_cast<std::int32_t>(RTT::WriteSuccess));
  ```

  Add a component input constructed with `RTT::ConnPolicy::data()`. Invoke its
  OPC UA `write` method twice before reading locally and assert that one local
  read returns the second value. This distinguishes the input's latest-value
  policy from the old forced circular buffer.

- [ ] **Step 2: Change proxy tests to require the Int32 method schema and
  behavior**

  Assert that proxy discovery rejects String status signatures and that normal
  port pumping accepts numeric status results. Retain the existing end-to-end
  checks that local proxy input samples reach the target input and target
  output samples reach a local proxy sink.

- [ ] **Step 3: Run the server and proxy tests and verify the red state**

  ```bash
  cmake --build toolchain/tools/rtt_opcua/build --parallel 2 \
    --target rtt_opcua_object_model_test rtt_opcua_task_context_proxy_test
  ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
    -R '^(rtt_opcua_object_model_test|rtt_opcua_task_context_proxy_test)$'
  ```

  Expected: failures report String status arguments and FIFO behavior on the
  published input.

- [ ] **Step 4: Use status codecs in method schemas and bridge callbacks**

  Change `portMethodArguments` to accept both codecs:

  ```cpp
  portMethodArguments(const TypeCodec &sample_codec,
                      const TypeCodec &status_codec, bool reads);
  ```

  Resolve `FlowStatus` for `read` and `WriteStatus` for `write` during snapshot
  preflight. Encode callback results through those codecs. Remove
  `flowStatusName` and `writeStatusName` so no port status crosses OPC UA as a
  free-form string.

- [ ] **Step 5: Select connection policy by published direction**

  In `PortBridge::create`, use these two branches:

  ```cpp
  if (auto *output = dynamic_cast<RTT::base::OutputPortInterface *>(&port)) {
    auto *input = dynamic_cast<RTT::base::InputPortInterface *>(peer.get());
    const auto policy = RTT::ConnPolicy::circularBuffer(
        static_cast<int>(buffer_size), RTT::ConnPolicy::LOCK_FREE);
    connected = input != nullptr && output->createConnection(*input, policy);
  } else if (auto *input =
                 dynamic_cast<RTT::base::InputPortInterface *>(&port)) {
    auto *output = dynamic_cast<RTT::base::OutputPortInterface *>(peer.get());
    connected = output != nullptr &&
                output->createConnection(*input, input->getDefaultPolicy());
  }
  ```

- [ ] **Step 6: Decode numeric statuses in client validation and proxy pumps**

  Validate the first output argument against the correct status codec's OPC UA
  datatype. Decode it through `TypeCodec::makeDataSource` and branch on the RTT
  enum value. Reject out-of-range values with a concrete remote-port error.

- [ ] **Step 7: Run the focused tests and verify the green state**

  Run the Step 3 commands again. Expected: both test executables pass, including
  the input-policy and numeric-schema cases.

- [ ] **Step 8: Commit the data-plane change in `rtt_opcua`**

  ```bash
  git -C toolchain/tools/rtt_opcua add \
    src/port_bridge.cpp src/object_model.cpp src/client_session.cpp \
    src/remote_port.cpp tests/object_model_test.cpp \
    tests/task_context_proxy_test.cpp
  git -C toolchain/tools/rtt_opcua commit \
    -m "feat: make OPC UA port transport type-safe"
  ```

### Task 3: Recursive Generated Port Services

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp`
- Test: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`
- Test: `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`

**Interfaces:**

- Consumes: the existing generic operation/property/attribute/port/service
  mapper at every RTT service level.
- Produces: `services/<port>/operations/...` for every service returned by RTT,
  including same-named generated port adapters.
- Produces: simultaneous proxy registration through `addLocalPort` and
  `addService`, allowing the two resources to share a name.
- Produces: path-specific preflight diagnostics for real service cycles and
  maximum-depth overflow; RTT's reserved `this` self-alias remains ignored.

- [ ] **Step 1: Add direct-server tests for both views of every port kind**

  Extend a generic fixture with input, output, and event input ports. Assert
  that each data-plane object exists and that these ordinary service methods
  also exist:

  ```text
  services/<input>/operations/name
  services/<input>/operations/connected
  services/<input>/operations/disconnect
  services/<input>/operations/read
  services/<input>/operations/clear
  services/<output>/operations/name
  services/<output>/operations/connected
  services/<output>/operations/disconnect
  services/<output>/operations/write
  services/<output>/operations/last
  ```

  Invoke `read`, `clear`, `write`, and `last` through the ordinary operation
  dispatcher and assert their RTT effects independently from the data-plane
  methods.

- [ ] **Step 2: Add a nested all-resource fixture and recursion-failure tests**

  Add a custom service containing an operation, property, attribute, constant,
  input port, and output port, plus one child service. Assert deterministic
  paths at both depths. Add fixtures that exceed the maintained depth limit and
  repeat a non-`this` service pointer in the active ancestry; assert strict
  publication failure and diagnostics containing the offending service path.

- [ ] **Step 3: Add proxy coexistence tests**

  After creating `TaskContextProxy`, assert both of these succeed for the same
  name:

  ```cpp
  BOOST_REQUIRE(proxy->getPort("command") != nullptr);
  BOOST_REQUIRE(proxy->provides()->getService("command") != nullptr);
  ```

  Call the generated service operations through RTT's generic operation
  interface and separately transfer samples through the mirrored proxy port.

- [ ] **Step 4: Run object-model and proxy tests and verify the red state**

  Run Task 2 Step 3. Expected: generated port-service node and coexistence
  assertions fail because traversal currently suppresses any service whose
  name matches a port.

- [ ] **Step 5: Remove port-name suppression and make recursion fail closed**

  Replace the traversal guard:

  ```cpp
  if (name == "this") {
    continue;
  }
  ```

  Use the same `appendServiceContents` function for generated and custom
  services. Before recursing, reject active-ancestry repeats and depth overflow
  by appending one `UnsupportedResource` whose path identifies the child
  service; do not insert a silently empty subtree.

- [ ] **Step 6: Preserve both resources in the proxy**

  Keep mirrored ports installed with `addLocalPort`, which deliberately does
  not synthesize a second adapter service, and install the discovered remote
  service with `addService`. The coexistence and cleanup tests prove this
  existing proxy installation contract; this task does not add a second proxy
  mapping implementation.

- [ ] **Step 7: Run focused and complete `rtt_opcua` tests**

  ```bash
  cmake --build toolchain/tools/rtt_opcua/build --parallel 2
  ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
    -R '^rtt_opcua_.*_test$'
  ```

  Expected: all `rtt_opcua` CTest cases pass.

- [ ] **Step 8: Commit the recursive service change in `rtt_opcua`**

  ```bash
  git -C toolchain/tools/rtt_opcua add \
    src/object_model.cpp tests/object_model_test.cpp \
    tests/task_context_proxy_test.cpp
  git -C toolchain/tools/rtt_opcua commit \
    -m "feat: publish RTT generated port services"
  ```

### Task 4: OCL Publication Integration

**Files:**

- Test: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`

**Interfaces:**

- Consumes: `RTT::opcua::ObjectModel::publishComponent(TaskContext&, ...)`.
- Produces: proof that `opcua.publishComponent(name)` publishes the complete
  two-plane model without OCL-specific mapping logic.

- [ ] **Step 1: Extend the OCL fixture with input/output ports and a nested
  service**

  Publish the local peer through `OpcUaDeploymentComponent`, create a
  `TaskContextProxy`, and assert root resources, nested resources, data ports,
  and generated same-named port services are all present.

- [ ] **Step 2: Exercise one resource of each kind through the proxy**

  Read/write a property and attribute, reject a constant write, call a root and
  nested operation, transfer one input and one output sample, and call one
  generated port-service operation.

- [ ] **Step 3: Run the OCL test and verify it fails before rebuilding against
  the new transport**

  ```bash
  cmake --build toolchain/tools/ocl/build --parallel 2 \
    --target ocl_opcua_deployment_test
  ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
    -R '^ocl_opcua_deployment_.*$'
  ```

  Expected before the updated `rtt_opcua` is linked: missing generated service
  assertions fail. After reconfiguration against Tasks 1-3, the same test must
  pass.

- [ ] **Step 4: Keep OCL as lifecycle-only glue**

  Do not change `OpcUaDeploymentComponent` or add resource-category branches
  to OCL. A failure here belongs to the generic `rtt_opcua` mapping and must be
  corrected in Tasks 1-3 before this integration test can pass.

- [ ] **Step 5: Reconfigure, build, and run OCL OPC UA integration**

  ```bash
  cmake -S toolchain/tools/ocl -B toolchain/tools/ocl/build \
    -DBUILD_TESTING=ON -DBUILD_TESTS=ON -DBUILD_DEPLOYMENT=ON \
    -DBUILD_TASKBROWSER=ON -DBUILD_OPCUA=ON
  cmake --build toolchain/tools/ocl/build --parallel 2 \
    --target ocl_opcua_deployment_test deployer-opcua ctaskbrowser-opcua
  ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
    -R '^ocl_opcua_deployment_.*$'
  ```

- [ ] **Step 6: Commit the OCL integration test**

  ```bash
  git -C toolchain/tools/ocl add \
    deployment/tests/opcua_deployment_test.cpp
  git -C toolchain/tools/ocl commit \
    -m "test: verify complete OPC UA component mapping"
  ```

### Task 5: Isolated `/tmp` Manual Component Probe

**Files:**

- Create outside Git:
  `/tmp/rtt-opcua-interface-probe.<unique>/CMakeLists.txt`
- Create outside Git:
  `/tmp/rtt-opcua-interface-probe.<unique>/interface_probe_component.cpp`
- Create outside Git:
  `/tmp/rtt-opcua-interface-probe.<unique>/interface_probe_client.cpp`
- Create outside Git:
  `/tmp/rtt-opcua-interface-probe.<unique>/probe.ops`
- Create outside Git:
  `/tmp/rtt-opcua-interface-probe.<unique>/run-deployer.sh`
- Create outside Git:
  `/tmp/rtt-opcua-interface-probe.<unique>/run-client.sh`

**Interfaces:**

- Consumes: the newly built RTT, `rtt_opcua`, OCL deployer, and canonical
  built-in type transport.
- Produces: direct browse/call/read/write evidence for every mapped category.
- Produces: no repository or application SDK code.

- [ ] **Step 1: Create a fresh probe directory and isolated overlay**

  ```bash
  mktemp -d /tmp/rtt-opcua-interface-probe.XXXXXX
  ```

  Install the rebuilt `rtt_opcua` and OCL artifacts into the probe's `prefix`
  and put that prefix first in `PATH`, `LD_LIBRARY_PATH`,
  `CMAKE_PREFIX_PATH`, `PKG_CONFIG_PATH`, and `RTT_COMPONENT_PATH`. The base
  toolchain prefix may supply unchanged dependencies, but all changed binaries
  and libraries must resolve from the probe overlay; record `ldd` evidence.

- [ ] **Step 2: Implement the application-neutral RTT component**

  The component must expose this matrix using `Int32`, `Float64`, `String`, and
  `Bool` only:

  ```text
  root
  |- operation: add(Int32, Int32) -> Int32
  |- property: Gain (read/write)
  |- attribute: Mode (read/write)
  |- constant: Model (read-only)
  |- input port: command (default data policy)
  |- event input port: trigger
  |- output port: feedback
  `- service: control
     |- operation: scale(Int32) -> Int32
     |- property: Offset
     |- attribute: Enabled
     |- constant: Unit
     |- input port: service_command
     |- output port: service_feedback
     `- service: nested
        `- operation: ping() -> Bool
  ```

- [ ] **Step 3: Build the plugin and direct OPC UA client**

  Configure and build under the same temporary directory. The client must use
  open62541pp directly, resolve namespace URI `urn:orocos:rtt`, construct
  deterministic NodeIds, and fail nonzero when any assertion fails.

- [ ] **Step 4: Start `deployer-opcua` and publish through the public API**

  The `.ops` script must import the temporary plugin, load
  `interface_probe`, call `opcua.start()`, and assert
  `opcua.publishComponent("interface_probe")`. Keep the deployer alive until
  the client finishes, with stdout/stderr captured under the probe directory.

- [ ] **Step 5: Verify all address-space and behavior checks directly**

  The client must verify:

  - root and nested category folders and metadata;
  - property and attribute read/write round trips;
  - constant read and `BadNotWritable` response;
  - root and nested operation results;
  - input and event-input data-plane writes reach local component reads;
  - component output samples return `FlowStatus` plus the correct value;
  - each port has its independent generated service with the expected methods;
  - generated `read`/`clear` and `write`/`last` preserve RTT behavior;
  - same-named `ports/<name>` and `services/<name>` NodeIds both exist; and
  - all status variants are scalar `Int32`, never String.

- [ ] **Step 6: Verify `ctaskbrowser-opcua` reconstruction**

  Connect the rebuilt client tool and capture a recursive interface listing
  showing the root resources, nested services, data ports, and same-named port
  services. Exercise at least one root operation and one nested operation from
  the proxy interface.

- [ ] **Step 7: Stop cleanly and retain the evidence path**

  Stop the deployer after the client succeeds, verify no endpoint process is
  left running, and retain the temporary path and logs for the final report.

### Task 6: Full Regression And Documentation Verification

**Files:**

- Modify: `docs/src/opcua-rtt-interface-mapping-design.md` only for factual
  corrections discovered during implementation.
- Modify: `docs/src/opcua-rtt-interface-mapping-plan.md` checkbox states as
  work completes.

**Interfaces:**

- Consumes: all preceding implementation and manual evidence.
- Produces: a clean verified package state and an auditable final report.

- [ ] **Step 1: Run the complete repository-supported OPC UA test workflow**

  ```bash
  ./tools/test-package.sh --prefix "$OROCOS_PREFIX" --target gnulinux rtt-opcua
  ```

  Expected: all native `rtt_opcua` and OCL OPC UA integration tests pass.

- [ ] **Step 2: Run documentation and repository checks**

  ```bash
  mdbook build docs
  mdbook test docs
  ruby tools/check-repository-policy.rb
  git diff --check
  ```

- [ ] **Step 3: Inspect package and root worktree state**

  ```bash
  git status --short
  git -C toolchain/tools/rtt_opcua status --short
  git -C toolchain/tools/ocl status --short
  ```

  Expected: only intentionally retained build directories or documented user
  files are untracked; no implementation change remains uncommitted.

- [ ] **Step 4: Commit final documentation evidence**

  ```bash
  git add docs/src/SUMMARY.md \
    docs/src/opcua-rtt-interface-mapping-design.md \
    docs/src/opcua-rtt-interface-mapping-plan.md
  git commit -m "docs: record complete RTT OPC UA mapping"
  ```

- [ ] **Step 5: Report exact verification evidence**

  Report package commit IDs, test counts, the retained `/tmp` probe path, the
  endpoint used, mapped paths checked, and any residual compatibility risk.
