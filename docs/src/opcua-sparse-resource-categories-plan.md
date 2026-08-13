# OPC UA Sparse Resource Categories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Omit empty OPC UA resource-category Objects uniformly while keeping
published RTT services and remote `TaskContextProxy` reconstruction intact.

**Architecture:** Keep the complete typed RTT snapshot and its existing strict
validation. Make the proxy tolerate `BadNodeIdUnknown` only while browsing a
deterministic category Object, then prune category `NodeSpec` entries that have
no direct mapped child before the snapshot fingerprint and commit are built.
OCL remains lifecycle-only glue and consumes the generic `rtt_opcua` behavior.

**Tech Stack:** C++20, Orocos RTT, `rtt_opcua`, open62541pp, Boost.Test, OCL,
CMake/CTest, mdBook.

## Global Constraints

- Apply the sparse rule uniformly to component roots, custom services, nested
  services, and RTT-generated port service adapters.
- Create `Operations`, `Properties`, `Attributes`, `Ports`, or `Services` only
  when that category has at least one mapped direct child.
- Preserve every mapped RTT service Object, including a completely empty
  service, so its identity and documentation remain browseable.
- Preserve existing deterministic NodeIds for every resource and every
  non-empty category.
- Treat `BadNodeIdUnknown` as an empty collection only when browsing the
  deterministic category Object itself.
- Continue rejecting missing or malformed resources and metadata inside an
  existing category.
- Keep `TaskContextProxy` compatible with older servers that expose empty
  category Objects.
- Preserve strict transactional publication, unsupported-resource diagnostics,
  component lifetime guards, idempotence, and snapshot fingerprinting.
- Do not add selector/filter syntax, authorization policy, application naming
  rules, or MetaNC dependencies.
- Do not add category-specific mapping logic to OCL.
- Use canonical built-in RTT types in tests and the manual probe.
- Commit changes separately in the `rtt_opcua`, OCL, and root documentation
  repositories. Never add package `build/` directories.

## File Structure

- Modify `toolchain/tools/rtt_opcua/src/client_session.cpp`: interpret a missing
  category Object as an empty discovery result without weakening child-schema
  validation.
- Modify `toolchain/tools/rtt_opcua/src/object_model.cpp`: remove empty category
  `NodeSpec` entries after recursive resource discovery.
- Modify `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`: prove
  sparse, dense, and malformed-resource proxy behavior.
- Modify `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`: prove exact
  sparse address-space shape at the root, custom-service, nested-service, and
  generated-port-service levels.
- Modify `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`: prove
  `publishComponent(name)` exposes sparse generated port services while proxy
  reconstruction remains complete.
- Modify outside Git
  `/tmp/rtt-opcua-interface-probe.7Ym4Ma/interface_probe_component.cpp`: add one
  empty service for manual identity-preservation evidence.
- Modify outside Git
  `/tmp/rtt-opcua-interface-probe.7Ym4Ma/interface_probe_client.cpp`: assert
  exact present and absent category paths.
- Modify `docs/src/opcua-sparse-resource-categories-plan.md`: record completion
  evidence after implementation.

---

### Task 1: Make Proxy Category Discovery Sparse-Compatible

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/client_session.cpp:35-55`
- Modify: `toolchain/tools/rtt_opcua/src/client_session.cpp:366-510`
- Modify: `toolchain/tools/rtt_opcua/src/client_session.cpp:512-640`
- Modify: `toolchain/tools/rtt_opcua/src/client_session.cpp:727-970`
- Test: `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`

**Interfaces:**

- Consumes: deterministic category paths produced by `modelPath(...)` and
  open62541pp browse results.
- Produces: `bool isMissingCategory(StatusCode) noexcept` and discovery methods
  that return an empty vector with an empty error only for a missing category
  Object.
- Preserves: all existing errors for a present category with missing child
  metadata, invalid direction, incompatible method schema, or duplicate names.

- [ ] **Step 1: Add deterministic NodeId and category-shaping test helpers**

  Add this test helper near `unusedLoopbackPort()`:

  ```cpp
  ::opcua::NodeId modelNodeId(
      std::uint16_t namespace_index,
      std::initializer_list<std::string_view> segments) {
    const std::vector<std::string_view> path_segments(segments);
    return ::opcua::NodeId(namespace_index,
                           RTT::opcua::makeNodePath(path_segments));
  }

  ::opcua::NodeId modelNodeId(
      std::uint16_t namespace_index,
      const std::vector<std::string_view> &segments) {
    return ::opcua::NodeId(namespace_index,
                           RTT::opcua::makeNodePath(segments));
  }
  ```

  Add helpers that shape an already-published server independently of whether
  its publisher is currently dense or sparse:

  ```cpp
  void removeNodeIfPresent(::opcua::Server &server,
                           const ::opcua::NodeId &id) {
    const ::opcua::StatusCode status =
        ::opcua::services::deleteNode(server, id, true);
    if (!status.isGood() &&
        status.get() != UA_STATUSCODE_BADNODEIDUNKNOWN) {
      throw ::opcua::BadStatus(status);
    }
  }

  void ensureEmptyCategory(::opcua::Server &server,
                           const ::opcua::NodeId &parent,
                           const ::opcua::NodeId &id,
                           std::string_view browse_name) {
    const auto existing = ::opcua::services::readNodeClass(server, id);
    if (existing) {
      return;
    }
    if (existing.code().get() != UA_STATUSCODE_BADNODEIDUNKNOWN) {
      throw ::opcua::BadStatus(existing.code());
    }
    ::opcua::ObjectAttributes attributes;
    attributes.setDisplayName(
        ::opcua::LocalizedText("en-US", browse_name));
    const auto added = ::opcua::services::addObject(
        server, parent, id, browse_name, attributes,
        ::opcua::ObjectTypeId::BaseObjectType,
        ::opcua::ReferenceTypeId::HasComponent);
    if (!added) {
      throw ::opcua::BadStatus(added.code());
    }
  }

  void removeCategories(
      ::opcua::Server &server, std::uint16_t namespace_index,
      const std::vector<std::string_view> &base,
      std::initializer_list<std::string_view> categories) {
    for (const std::string_view category : categories) {
      auto path = base;
      path.push_back(category);
      removeNodeIfPresent(server, modelNodeId(namespace_index, path));
    }
  }

  void ensureDenseCategories(
      ::opcua::Server &server, std::uint16_t namespace_index,
      const std::vector<std::string_view> &base) {
    const auto parent = modelNodeId(namespace_index, base);
    for (const auto &[segment, browse_name] :
         std::array<std::pair<std::string_view, std::string_view>, 5U>{{
             {"operations", "Operations"},
             {"properties", "Properties"},
             {"attributes", "Attributes"},
             {"ports", "Ports"},
             {"services", "Services"},
         }}) {
      auto path = base;
      path.push_back(segment);
      ensureEmptyCategory(server, parent,
                          modelNodeId(namespace_index, path), browse_name);
    }
  }
  ```

  Add the required `attribute_highlevel.hpp`, `exception.hpp`,
  `<initializer_list>`, `<string_view>`, and `<utility>` includes; the test
  already includes `nodemanagement.hpp` and `<array>`.

- [ ] **Step 2: Extend the proxy fixtures with sparse-root and empty services**

  Extend `ProxyTarget` with two empty services so sparse and dense category
  shapes can be exercised without removing either service Object:

  ```cpp
  RTT::Service::shared_ptr sparse_empty =
      RTT::Service::Create("sparse_empty");
  sparse_empty->doc("Intentionally sparse empty service.");
  BOOST_REQUIRE(provides()->addService(sparse_empty));

  RTT::Service::shared_ptr dense_empty =
      RTT::Service::Create("dense_empty");
  dense_empty->doc("Legacy dense empty service.");
  BOOST_REQUIRE(provides()->addService(dense_empty));
  ```

  Add a second fixture whose root contains only the standard `TaskContext`
  operations and attributes:

  ```cpp
  class SparseRootTarget final : public RTT::TaskContext {
  public:
    SparseRootTarget()
        : RTT::TaskContext("remote/sparse-root",
                           RTT::TaskContext::PreOperational) {}
  };
  ```

- [ ] **Step 3: Write the failing sparse-category proxy test**

  Add
  `proxy_treats_missing_category_objects_as_empty_collections`. Publish a
  `ProxyTarget`, then shape the address space with this exact invocation. The
  helper makes deletion idempotent so the test remains valid after the real
  publisher becomes sparse, while `dense_empty` explicitly models an older
  dense server regardless of publisher version.

  ```cpp
  const std::uint16_t namespace_index = *server.namespaceIndex();
  const std::string component_name = target.getName();
  BOOST_REQUIRE_MESSAGE(
      server.invoke(
          [&](::opcua::Server &native) {
            removeCategories(
                native, namespace_index,
                {"components", component_name, "services", "Command"},
                {"properties", "attributes", "ports", "services"});
            removeCategories(
                native, namespace_index,
                {"components", component_name, "services", "math",
                 "services", "advanced"},
                {"properties", "attributes", "ports", "services"});
            removeCategories(
                native, namespace_index,
                {"components", component_name, "services", "sparse_empty"},
                {"operations", "properties", "attributes", "ports",
                 "services"});
            ensureDenseCategories(
                native, namespace_index,
                {"components", component_name, "services", "dense_empty"});
          },
          std::chrono::seconds(1), &error),
      error);
  ```

  Create `TaskContextProxy` and assert:

  ```cpp
  BOOST_REQUIRE_MESSAGE(proxy != nullptr, error);
  BOOST_REQUIRE(proxy->provides()->getService("Command"));
  BOOST_REQUIRE(
      proxy->provides()->getService("Command")->getOperation("read"));
  BOOST_REQUIRE(proxy->provides()->getService("sparse_empty"));
  BOOST_TEST(proxy->provides()->getService("sparse_empty")->doc() ==
             "Intentionally sparse empty service.");
  BOOST_TEST(proxy->provides()
                 ->getService("sparse_empty")
                 ->getOperationNames()
                 .empty());
  BOOST_TEST(proxy->provides()
                 ->getService("sparse_empty")
                 ->properties()
                 ->getPropertyNames()
                 .empty());
  BOOST_TEST(proxy->provides()
                 ->getService("sparse_empty")
                 ->getAttributeNames()
                 .empty());
  BOOST_TEST(proxy->provides()
                 ->getService("sparse_empty")
                 ->getPortNames()
                 .empty());
  BOOST_TEST(proxy->provides()
                 ->getService("sparse_empty")
                 ->getProviderNames()
                 .empty());
  BOOST_REQUIRE(proxy->provides()->getService("dense_empty"));
  BOOST_TEST(proxy->provides()->getService("dense_empty")->doc() ==
             "Legacy dense empty service.");
  BOOST_TEST(proxy->provides()
                 ->getService("dense_empty")
                 ->getOperationNames()
                 .empty());
  BOOST_TEST(proxy->provides()
                 ->getService("dense_empty")
                 ->properties()
                 ->getPropertyNames()
                 .empty());
  BOOST_TEST(proxy->provides()
                 ->getService("dense_empty")
                 ->getAttributeNames()
                 .empty());
  BOOST_TEST(proxy->provides()
                 ->getService("dense_empty")
                 ->getPortNames()
                 .empty());
  BOOST_TEST(proxy->provides()
                 ->getService("dense_empty")
                 ->getProviderNames()
                 .empty());
  BOOST_REQUIRE(proxy->provides()
                    ->getService("math")
                    ->getService("advanced")
                    ->getOperation("negate"));
  ```

- [ ] **Step 4: Write the failing sparse-root proxy test**

  Add `proxy_reconstructs_a_sparse_component_root`. Publish a
  `SparseRootTarget`, remove the candidate empty category Objects, and leave
  the standard non-empty `Operations` and `Attributes` categories unchanged:

  ```cpp
  const std::uint16_t namespace_index = *server.namespaceIndex();
  const std::string component_name = target.getName();
  BOOST_REQUIRE_MESSAGE(
      server.invoke(
          [&](::opcua::Server &native) {
            removeCategories(native, namespace_index,
                             {"components", component_name},
                             {"properties", "ports", "services"});
          },
          std::chrono::seconds(1), &error),
      error);
  ```

  Create the proxy and assert:

  ```cpp
  BOOST_REQUIRE_MESSAGE(proxy != nullptr, error);
  BOOST_TEST(proxy->getName() == target.getName());
  BOOST_TEST(proxy->provides()->properties()->getPropertyNames().empty());
  BOOST_TEST(proxy->ports()->getPortNames().empty());
  BOOST_TEST(proxy->provides()->getProviderNames().empty());
  ```

  RTT's reserved `this` alias is resolved by `getService("this")`; it is not
  stored in `getProviderNames()`, so an empty list proves no child service was
  reconstructed.

- [ ] **Step 5: Add the strict missing-metadata characterization test**

  Add `proxy_rejects_missing_metadata_inside_a_present_category`. Publish a
  fresh `ProxyTarget`, delete only the port type node while leaving `Ports` and
  `Ports/Feedback` present:

  ```cpp
  const std::uint16_t namespace_index = *server.namespaceIndex();
  const auto type_id = modelNodeId(
      namespace_index,
      {"components", target.getName(), "ports", "Feedback", "type"});
  BOOST_REQUIRE_MESSAGE(
      server.invoke(
          [&](::opcua::Server &native) {
            const ::opcua::StatusCode status =
                ::opcua::services::deleteNode(native, type_id, true);
            if (!status.isGood()) {
              throw ::opcua::BadStatus(status);
            }
          },
          std::chrono::seconds(1), &error),
      error);
  ```

  Assert:

  ```cpp
  BOOST_TEST(proxy == nullptr);
  BOOST_TEST(error.find("failed to read RTT port type metadata") !=
             std::string::npos);
  BOOST_TEST(error.find("BadNodeIdUnknown") != std::string::npos);
  ```

- [ ] **Step 6: Run focused tests and verify the red/characterization state**

  Run:

  ```bash
  cmake --build toolchain/tools/rtt_opcua/build --parallel 2 \
    --target rtt_opcua_task_context_proxy_test
  toolchain/tools/rtt_opcua/build/rtt_opcua_task_context_proxy_test \
    --run_test=proxy_treats_missing_category_objects_as_empty_collections
  toolchain/tools/rtt_opcua/build/rtt_opcua_task_context_proxy_test \
    --run_test=proxy_reconstructs_a_sparse_component_root
  toolchain/tools/rtt_opcua/build/rtt_opcua_task_context_proxy_test \
    --run_test=proxy_rejects_missing_metadata_inside_a_present_category
  ```

  Expected before implementation:

  - both sparse-category tests fail with `BadNodeIdUnknown` while discovering a
    deleted category;
  - missing-metadata test passes, proving the strict behavior that must remain.

- [ ] **Step 7: Implement category-only `BadNodeIdUnknown` tolerance**

  Add this helper beside `invalidatesInterface`:

  ```cpp
  bool isMissingCategory(::opcua::StatusCode status) noexcept {
    return status.get() == UA_STATUSCODE_BADNODEIDUNKNOWN;
  }
  ```

  In `discoverOperations`, change only the failure branch immediately after
  browsing the category folder:

  ```cpp
  if (!browse_result) {
    if (isMissingCategory(browse_result.code())) {
      last_error_.clear();
      assignError(error, "");
      return operations;
    }
    last_error_ = statusMessage("failed to discover remote RTT operations",
                                browse_result.code());
    assignError(error, last_error_);
    return operations;
  }
  ```

  Apply the same category-only branch to the other three browse sites with
  their exact vectors and existing diagnostics:

  ```cpp
  // discoverValues
  if (!browse_result) {
    if (isMissingCategory(browse_result.code())) {
      last_error_.clear();
      assignError(error, "");
      return values;
    }
    last_error_ = statusMessage("failed to discover remote RTT " +
                                    std::string(category_name),
                                browse_result.code());
    assignError(error, last_error_);
    return values;
  }

  // discoverServices
  if (!browse_result) {
    if (isMissingCategory(browse_result.code())) {
      last_error_.clear();
      assignError(error, "");
      return services;
    }
    last_error_ = statusMessage("failed to discover remote RTT services",
                                browse_result.code());
    assignError(error, last_error_);
    return services;
  }

  // discoverPorts
  if (!browse_result) {
    if (isMissingCategory(browse_result.code())) {
      last_error_.clear();
      assignError(error, "");
      return ports;
    }
    last_error_ = statusMessage("failed to discover remote RTT ports",
                                browse_result.code());
    assignError(error, last_error_);
    return ports;
  }
  ```

  Do not apply this helper to component lookup, service-description reads,
  `rttType`, port `type`, port `direction`, method arguments, or method lookup.

- [ ] **Step 8: Run proxy tests and verify green behavior**

  Run:

  ```bash
  cmake --build toolchain/tools/rtt_opcua/build --parallel 2 \
    --target rtt_opcua_task_context_proxy_test
  ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
    -R '^rtt_opcua_task_context_proxy_test$'
  ```

  Expected: sparse root and nested categories, the deliberately dense empty
  service, missing-metadata rejection, and all existing proxy behavior pass.

- [ ] **Step 9: Commit proxy compatibility**

  ```bash
  git -C toolchain/tools/rtt_opcua add \
    src/client_session.cpp tests/task_context_proxy_test.cpp
  git -C toolchain/tools/rtt_opcua commit \
    -m "feat: accept sparse OPC UA resource categories"
  ```

### Task 2: Prune Empty Category Objects From Published Snapshots

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp:27-42`
- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp:1035-1048`
- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp:1179-1235`
- Test: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp:134-156`
- Test: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp:306-348`
- Test: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp:629-935`

**Interfaces:**

- Consumes: the complete recursively populated `NodeMap` and each owning
  service's deterministic path.
- Produces: `pruneEmptyResourceFolders(NodeMap&, const std::string&)`, called
  once at the end of every `appendServiceContents` recursion level.
- Preserves: service Objects, resource NodeIds, snapshot validation, and
  fingerprint generation over the final committed node set.

- [ ] **Step 1: Extend the static fixture with an empty service**

  Extend `StaticSnapshotComponent` with the initializer and member shown below,
  then document and register it on the root service:

  ```cpp
  // Constructor initializer list
  limits(RTT::Service::Create("limits")),
  empty(RTT::Service::Create("empty")) {

  // Constructor body
  empty->doc("Intentionally empty service");
  BOOST_REQUIRE(provides()->addService(empty));

  // Member declarations
  RTT::Service::shared_ptr limits;
  RTT::Service::shared_ptr empty;
  ```

  Keep `limits` as the existing property-only service and `Command` as the
  existing generated operation-only port service. Together these fixtures
  cover empty, single-category, and generated-service cases.

- [ ] **Step 2: Write the failing sparse component-root test**

  Add `publish_component_omits_empty_root_categories` using the existing
  `OperationComponent`. It contributes operations, while the standard
  `TaskContext` interface contributes attributes; it has no registered root
  properties, ports, or child services.

  Publish it, connect a client, and assert these positive paths:

  ```text
  components/calculator
  components/calculator/operations
  components/calculator/attributes
  ```

  Assert `BadNodeIdUnknown` for:

  ```text
  components/calculator/properties
  components/calculator/ports
  components/calculator/services
  ```

  This is the direct publisher counterpart to Task 1's sparse-root proxy test.

- [ ] **Step 3: Write the failing sparse service assertions**

  In `publish_component_creates_one_complete_static_snapshot`, assert these
  positive paths:

  ```text
  components/arm%2Fleft/services/Command/operations
  components/arm%2Fleft/services/motion%2Fraw/services
  components/arm%2Fleft/services/motion%2Fraw/services/limits/properties
  components/arm%2Fleft/services/empty
  ```

  Assert `BadNodeIdUnknown` for all four empty categories below both an input
  port's generated service (`Command`) and an output port's generated service
  (`Feedback`):

  ```text
  components/arm%2Fleft/services/Command/properties
  components/arm%2Fleft/services/Command/attributes
  components/arm%2Fleft/services/Command/ports
  components/arm%2Fleft/services/Command/services

  components/arm%2Fleft/services/Feedback/properties
  components/arm%2Fleft/services/Feedback/attributes
  components/arm%2Fleft/services/Feedback/ports
  components/arm%2Fleft/services/Feedback/services

  components/arm%2Fleft/services/motion%2Fraw/services/MotionFeedback/properties
  components/arm%2Fleft/services/motion%2Fraw/services/MotionFeedback/attributes
  components/arm%2Fleft/services/motion%2Fraw/services/MotionFeedback/ports
  components/arm%2Fleft/services/motion%2Fraw/services/MotionFeedback/services
  ```

  Also assert the single-category and completely empty custom-service cases:

  ```text
  components/arm%2Fleft/services/motion%2Fraw/services/limits/operations
  components/arm%2Fleft/services/motion%2Fraw/services/limits/attributes
  components/arm%2Fleft/services/motion%2Fraw/services/limits/ports
  components/arm%2Fleft/services/motion%2Fraw/services/limits/services

  components/arm%2Fleft/services/empty/operations
  components/arm%2Fleft/services/empty/properties
  components/arm%2Fleft/services/empty/attributes
  components/arm%2Fleft/services/empty/ports
  components/arm%2Fleft/services/empty/services
  ```

  Use a helper that checks both failure and its exact status:

  ```cpp
  void requireMissingNode(::opcua::Client &client, const ::opcua::NodeId &id) {
    const auto result = ::opcua::services::readNodeClass(client, id);
    BOOST_REQUIRE(!result);
    BOOST_TEST(result.code() == UA_STATUSCODE_BADNODEIDUNKNOWN);
  }
  ```

  Read the empty service Object's description and prove that pruning did not
  discard service metadata:

  ```cpp
  const auto empty_service_id = modelNodeId(
      namespace_index,
      {"components", "arm/left", "services", "empty"});
  const auto empty_description =
      ::opcua::services::readDescription(client, empty_service_id);
  BOOST_REQUIRE(empty_description);
  BOOST_TEST(empty_description->text() == "Intentionally empty service");
  ```

- [ ] **Step 4: Run the object-model tests and verify they fail on dense folders**

  ```bash
  cmake --build toolchain/tools/rtt_opcua/build --parallel 2 \
    --target rtt_opcua_object_model_test
  toolchain/tools/rtt_opcua/build/rtt_opcua_object_model_test \
    --run_test=publish_component_omits_empty_root_categories
  toolchain/tools/rtt_opcua/build/rtt_opcua_object_model_test \
    --run_test=publish_component_creates_one_complete_static_snapshot
  ```

  Expected: each test reaches a `requireMissingNode` assertion and fails
  because the current publisher creates all five categories unconditionally.

- [ ] **Step 5: Define one shared category table**

  Add `<array>` and replace the local initializer list in
  `appendResourceFolders` with:

  ```cpp
  constexpr std::array<std::pair<std::string_view, std::string_view>, 5U>
      kResourceCategories{{
          {"operations", "Operations"},
          {"properties", "Properties"},
          {"attributes", "Attributes"},
          {"ports", "Ports"},
          {"services", "Services"},
      }};
  ```

  `appendResourceFolders` continues to create candidate folders from this table
  before mapping resources. This preserves the existing insertion logic and
  keeps pruning separate from discovery. Replace its loop with:

  ```cpp
  for (const auto &category : kResourceCategories) {
    insertNode(nodes,
               objectSpec(appendNodeSegment(owner_path, category.first),
                          owner_path, std::string(category.second),
                          description));
  }
  ```

- [ ] **Step 6: Implement direct-child pruning after recursive discovery**

  Add:

  ```cpp
  void pruneEmptyResourceFolders(NodeMap &nodes,
                                 const std::string &owner_path) {
    for (const auto &category : kResourceCategories) {
      const std::string category_path =
          appendNodeSegment(owner_path, category.first);
      const bool has_direct_child = std::ranges::any_of(
          nodes, [&category_path](const auto &entry) {
            return entry.second.parent_path == category_path;
          });
      if (!has_direct_child) {
        nodes.erase(category_path);
      }
    }
  }
  ```

  Call `pruneEmptyResourceFolders(nodes, service_path)` after the child-service
  loop in `appendServiceContents` and before erasing the service from
  `ancestry`. Direct-parent matching is required: it keeps `Services` when it
  owns an empty child service Object, but removes the five category Objects
  below that empty child.

- [ ] **Step 7: Run focused and complete `rtt_opcua` tests**

  ```bash
  cmake --build toolchain/tools/rtt_opcua/build --parallel 2
  ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
    -R '^(rtt_opcua_object_model_test|rtt_opcua_task_context_proxy_test)$'
  ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure
  ```

  Expected: 10 of 10 package tests pass. The proxy suite proves that the newly
  sparse publisher remains reconstructable and that intentionally present
  empty category Objects remain accepted.

- [ ] **Step 8: Install the updated generic transport into the feature overlay**

  ```bash
  cmake --install toolchain/tools/rtt_opcua/build
  ```

  Expected: the install prefix from `CMakeCache.txt`,
  `.worktrees/opcua-interface-mapping/install`, receives the updated library,
  plugin, headers, and pkg-config metadata.

- [ ] **Step 9: Commit sparse publication**

  ```bash
  git -C toolchain/tools/rtt_opcua add \
    src/object_model.cpp tests/object_model_test.cpp
  git -C toolchain/tools/rtt_opcua commit \
    -m "feat: omit empty OPC UA resource categories"
  ```

### Task 3: Verify Sparse Mapping Through `publishComponent`

**Files:**

- Modify: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`
- Do not modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.cpp`
- Do not modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.hpp`

**Interfaces:**

- Consumes: `OpcUaDeploymentComponent::publishComponent(const std::string&)`
  and the installed sparse `RTT::opcua::ObjectModel` implementation.
- Produces: direct address-space evidence that OCL publishes the generic sparse
  schema, plus existing `TaskContextProxy` behavioral evidence.

- [ ] **Step 1: Add direct OPC UA browse helpers to the OCL test**

  Include:

  ```cpp
  #include <rtt/opcua/node_id.hpp>
  #include <open62541pp/client.hpp>
  #include <open62541pp/services/attribute_highlevel.hpp>
  #include <initializer_list>
  #include <limits>
  ```

  Add these helpers near `unusedLoopbackPort()`:

  ```cpp
  ::opcua::NodeId modelNodeId(
      std::uint16_t namespace_index,
      std::initializer_list<std::string_view> segments) {
    const std::vector<std::string_view> path_segments(segments);
    return ::opcua::NodeId(namespace_index,
                           RTT::opcua::makeNodePath(path_segments));
  }

  std::uint16_t namespaceIndex(::opcua::Client &client) {
    const auto namespaces = client.namespaceArray();
    const auto found = std::find(namespaces.begin(), namespaces.end(),
                                 RTT::opcua::kNamespaceUri);
    if (found == namespaces.end()) {
      throw std::runtime_error("RTT OPC UA namespace URI is missing");
    }
    const auto index = std::distance(namespaces.begin(), found);
    if (index < 0 ||
        index > std::numeric_limits<std::uint16_t>::max()) {
      throw std::runtime_error("RTT OPC UA namespace index is invalid");
    }
    return static_cast<std::uint16_t>(index);
  }

  void requireMissingNode(::opcua::Client &client,
                          const ::opcua::NodeId &id) {
    const auto result = ::opcua::services::readNodeClass(client, id);
    BOOST_REQUIRE(!result);
    BOOST_TEST(result.code() == UA_STATUSCODE_BADNODEIDUNKNOWN);
  }
  ```

- [ ] **Step 2: Add sparse assertions to the deployer integration test**

  In `strict_publication_is_static_and_idempotent`, immediately after:

  ```cpp
  BOOST_REQUIRE(deployer.publishComponent(complete.getName()));
  ```

  connect an open62541pp client and assert:

  ```cpp
  ::opcua::Client client;
  client.connect(deployer.opcUaEndpointUrl());
  const std::uint16_t namespace_index = namespaceIndex(client);
  BOOST_REQUIRE(::opcua::services::readNodeClass(
      client, modelNodeId(namespace_index,
                          {"components", "CompleteMapping", "services",
                           "Command", "operations"})));
  for (const std::string_view category :
       {"properties", "attributes", "ports", "services"}) {
    requireMissingNode(
        client,
        modelNodeId(namespace_index,
                    {"components", "CompleteMapping", "services",
                     "Command", category}));
  }
  client.disconnect();
  ```

  Disconnect the direct client, then leave the existing proxy creation and all
  operation/property/attribute/port/generated-service checks unchanged.

- [ ] **Step 3: Reconfigure OCL against the feature overlay**

  ```bash
  feature_root=/home/liufang/MetaNC/rock-orocos/.worktrees/opcua-interface-mapping
  base_prefix=/home/liufang/.orocos/toolchain
  PKG_CONFIG_PATH="$feature_root/install/lib/pkgconfig:$base_prefix/lib/pkgconfig" \
    cmake -S toolchain/tools/ocl -B toolchain/tools/ocl/build-overlay \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_INSTALL_PREFIX="$feature_root/install" \
      -DCMAKE_PREFIX_PATH="$feature_root/install;$base_prefix" \
      -DBUILD_TESTING=ON -DBUILD_TESTS=ON -DBUILD_DEPLOYMENT=ON \
      -DBUILD_TASKBROWSER=ON -DBUILD_OPCUA=ON
  ```

  Inspect `build-overlay/CMakeCache.txt` and require
  `RTT_OPCUA_LIBRARY_DIRS` to list the feature overlay before the base prefix.

- [ ] **Step 4: Build and run the OCL OPC UA integration suite**

  ```bash
  cmake --build toolchain/tools/ocl/build-overlay --parallel 2 \
    --target ocl_opcua_deployment_test deployer-opcua ctaskbrowser-opcua
  ctest --test-dir toolchain/tools/ocl/build-overlay --output-on-failure \
    -R '^ocl_opcua_deployment_.*$'
  ```

  Expected: all six OCL OPC UA deployment cases pass, including the direct
  sparse-category assertions and existing complete proxy behavior.

- [ ] **Step 5: Install OCL into the feature overlay**

  ```bash
  cmake --install toolchain/tools/ocl/build-overlay
  ```

- [ ] **Step 6: Commit OCL acceptance coverage**

  ```bash
  git -C toolchain/tools/ocl add deployment/tests/opcua_deployment_test.cpp
  git -C toolchain/tools/ocl commit \
    -m "test: verify sparse OPC UA component categories"
  ```

### Task 4: Rebuild And Run The Temporary Manual Probe

**Files:**

- Modify outside Git:
  `/tmp/rtt-opcua-interface-probe.7Ym4Ma/interface_probe_component.cpp`
- Modify outside Git:
  `/tmp/rtt-opcua-interface-probe.7Ym4Ma/interface_probe_client.cpp`
- Rebuild outside Git: `/tmp/rtt-opcua-interface-probe.7Ym4Ma/build/`
- Refresh outside Git: `/tmp/rtt-opcua-interface-probe.7Ym4Ma/prefix/`

**Interfaces:**

- Consumes: feature-overlay `rtt_opcua` and OCL artifacts from Tasks 2 and 3.
- Produces: direct browse/call/read/write evidence and TaskBrowser evidence for
  the sparse schema without modifying any repository.

- [ ] **Step 1: Add an intentionally empty probe service**

  Add `empty_(RTT::Service::Create("empty"))` to
  `InterfaceProbeComponent`, document it, and register it at the root:

  ```cpp
  // Constructor initializer list
  empty_(RTT::Service::Create("empty"))

  // Constructor body
  empty_->doc("Intentionally empty service.");
  provides()->addService(empty_);

  // Member declaration
  RTT::Service::shared_ptr empty_;
  ```

- [ ] **Step 2: Replace dense category assertions with exact sparse assertions**

  Add:

  ```cpp
  void requireNoNode(::opcua::Client &client, const ::opcua::NodeId &id,
                     std::string_view label) {
    const auto result = ::opcua::services::readNodeClass(client, id);
    require(!result && result.code() == UA_STATUSCODE_BADNODEIDUNKNOWN,
            "unexpected OPC UA node: " + std::string(label));
  }
  ```

  Replace `requireCategories` with a helper that checks all five known
  categories against an explicit present set:

  ```cpp
  void requireCategoryShape(
      ::opcua::Client &client, std::uint16_t ns,
      const std::vector<std::string_view> &base,
      std::initializer_list<std::string_view> present,
      std::string_view label) {
    for (const std::string_view category :
         {"operations", "properties", "attributes", "ports", "services"}) {
      auto path = base;
      path.push_back(category);
      const bool expected =
          std::find(present.begin(), present.end(), category) != present.end();
      if (expected) {
        requireNode(client, node(ns, path),
                    std::string(label) + "." + std::string(category));
      } else {
        requireNoNode(client, node(ns, path),
                      std::string(label) + "." + std::string(category));
      }
    }
  }
  ```

  In `verifyInterface`, use these exact calls:

  ```cpp
  requireCategoryShape(
      client, ns, {"components", "interface_probe"},
      {"operations", "properties", "attributes", "ports", "services"},
      "interface_probe");
  requireCategoryShape(
      client, ns,
      {"components", "interface_probe", "services", "control"},
      {"operations", "properties", "attributes", "ports", "services"},
      "control");
  requireCategoryShape(
      client, ns,
      {"components", "interface_probe", "services", "control", "services",
       "nested"},
      {"operations"}, "control.nested");
  requireCategoryShape(
      client, ns,
      {"components", "interface_probe", "services", "empty"}, {}, "empty");
  requireNode(client,
              node(ns, {"components", "interface_probe", "services",
                        "empty"}),
              "empty service");
  ```

  At the start of `verifyGeneratedServiceCommon`, add:

  ```cpp
  requireCategoryShape(client, ns, service_path, {"operations"}, name);
  ```

  That shared path exercises all root and nested input, event-input, and output
  generated port services already passed through the helper. The resulting
  expectations are:

  ```text
  interface_probe                              all five present
  interface_probe/services/control             all five present
  interface_probe/services/control/services/nested
                                               Operations only
  every generated port service                 Operations only
  interface_probe/services/empty               no categories present
  ```

  Continue all existing value, operation, port data-plane, and generated
  service behavior checks unchanged.

- [ ] **Step 3: Refresh the probe prefix and rebuild the probe**

  ```bash
  feature_root=/home/liufang/MetaNC/rock-orocos/.worktrees/opcua-interface-mapping
  probe_root=/tmp/rtt-opcua-interface-probe.7Ym4Ma
  base_prefix=/home/liufang/.orocos/toolchain

  cmake --install "$feature_root/toolchain/tools/rtt_opcua/build" \
    --prefix "$probe_root/prefix"
  cmake --install "$feature_root/toolchain/tools/ocl/build-overlay" \
    --prefix "$probe_root/prefix"

  CMAKE_PREFIX_PATH="$probe_root/prefix:$base_prefix" \
  PKG_CONFIG_PATH="$probe_root/prefix/lib/pkgconfig:$base_prefix/lib/pkgconfig" \
    cmake -S "$probe_root" -B "$probe_root/build" \
      -DCMAKE_INSTALL_PREFIX="$probe_root/prefix"
  cmake --build "$probe_root/build" --parallel 2
  cmake --install "$probe_root/build"
  ```

  Confirm the changed binaries resolve `rtt_opcua` and OCL libraries from the
  probe prefix before running:

  ```bash
  ldd "$probe_root/prefix/bin/deployer-opcua-gnulinux" \
    | rg "$probe_root/prefix"
  ldd "$probe_root/prefix/bin/interface-probe-client" \
    | rg "$probe_root/prefix"
  ```

  Expected: both commands print probe-prefix library paths; neither changed
  binary resolves `orocos-rtt-opcua`, `rtt-transport-opcua`, or OCL from the
  base prefix.

- [ ] **Step 4: Start the deployer using the temporary executable**

  In terminal one:

  ```bash
  cd /tmp/rtt-opcua-interface-probe.7Ym4Ma
  ./run-deployer.sh 4842
  ```

  Do not use the unqualified base-prefix `deployer-opcua`; it cannot discover
  the temporary component package.

- [ ] **Step 5: Run direct and TaskBrowser clients**

  In terminal two:

  ```bash
  cd /tmp/rtt-opcua-interface-probe.7Ym4Ma
  ./run-client.sh opc.tcp://127.0.0.1:4842/rtt
  ./run-taskbrowser.sh opc.tcp://127.0.0.1:4842/rtt
  ```

  Expected direct result:

  ```text
  direct OPC UA interface mapping probe passed
  ```

  Expected TaskBrowser calls remain:

  ```text
  add(20, 22)                 = 42
  control.scale(10)           = 45
  control.nested.ping()       = true
  ```

- [ ] **Step 6: Stop and verify clean shutdown**

  Enter `quit` in terminal one, then run:

  ```bash
  ! ss -ltnp | rg ':4842\b'
  ! ps -ef | rg '[d]eployer-opcua-gnulinux.*4842'
  ```

  Retain the probe directory and logs as temporary evidence. Do not add them to
  Git.

### Task 5: Full Regression And Completion Evidence

**Files:**

- Modify: `docs/src/opcua-sparse-resource-categories-plan.md`
- Modify: `docs/src/opcua-rtt-interface-mapping-design.md` only if verified
  implementation behavior requires a factual correction.

**Interfaces:**

- Consumes: package commits, OCL acceptance results, and manual-probe logs.
- Produces: fresh regression evidence and a clean auditable feature state.

- [ ] **Step 1: Run all `rtt_opcua` tests from a fresh build invocation**

  ```bash
  cmake --build toolchain/tools/rtt_opcua/build --parallel 2
  ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure
  ```

  Expected: 10 of 10 tests pass.

- [ ] **Step 2: Re-run all maintained OCL OPC UA integration cases**

  ```bash
  cmake --build toolchain/tools/ocl/build-overlay --parallel 2 \
    --target ocl_opcua_deployment_test deployer-opcua ctaskbrowser-opcua
  ctest --test-dir toolchain/tools/ocl/build-overlay --output-on-failure \
    -R '^ocl_opcua_deployment_.*$'
  ```

  Expected: 6 of 6 deployment cases pass.

- [ ] **Step 3: Run documentation and root policy checks**

  ```bash
  verify_root="$(mktemp -d /tmp/orocos-opcua-sparse-verify.XXXXXX)"
  mdbook build docs --dest-dir "$verify_root/book"
  mdbook test docs
  ruby tools/check-repository-policy.rb
  git diff --check
  git -C toolchain/tools/rtt_opcua diff --check
  git -C toolchain/tools/ocl diff --check
  ```

- [ ] **Step 4: Record exact completion evidence in this plan**

  Add a `## Completion Evidence` section immediately below the global
  constraints containing:

  - the two `rtt_opcua` commit hashes;
  - the OCL test commit hash;
  - counts from both CTest runs;
  - the retained `/tmp` probe path and its direct-client result;
  - the TaskBrowser call results;
  - mdBook and repository-policy results.

  Mark checkboxes only for steps supported by fresh command output.

- [ ] **Step 5: Inspect all three repository states**

  ```bash
  git status --short --branch
  git -C toolchain/tools/rtt_opcua status --short --branch
  git -C toolchain/tools/ocl status --short --branch
  ```

  Expected: root contains only the intentional completion-evidence edit before
  its final commit; `rtt_opcua` may retain only its pre-existing untracked
  `build/`; OCL is clean.

- [ ] **Step 6: Commit completion evidence**

  ```bash
  git add docs/src/opcua-sparse-resource-categories-plan.md \
    docs/src/opcua-rtt-interface-mapping-design.md
  git commit -m "docs: record sparse OPC UA category verification"
  ```

  Omit the design file from `git add` when no factual correction was required.
