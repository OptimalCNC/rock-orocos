# OPC UA Port Direction Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace free-form RTT port-direction strings with one strict,
shared, read-only scalar OPC UA `Int32` contract: input is `0` and output is
`1`.

**Architecture:** Install a focused `PortDirection` protocol header from
`rtt_opcua`, then use it in both object-model publication and
`TaskContextProxy` discovery. The publisher classifies RTT ports before the
transactional snapshot is committed; the proxy validates the exact Variant
shape before selecting its local mirror port and data-plane method. OCL keeps
using the generic mapping and adds only end-to-end acceptance coverage.

**Tech Stack:** C++20, Orocos RTT, `rtt_opcua`, open62541pp 0.21.2,
Boost.Test, OCL, CMake/CTest, mdBook, and the retained temporary interface
probe.

## Completion Evidence

- `rtt_opcua`: `ec9f0aa032f4830de6cfae79a865292cb077d6dd` (`feat: define OPC UA port direction codes`) and `64fb2772a97804ee291243688401af1cad932486` (`feat: map OPC UA port direction as Int32`).
- OCL: `ca65b0f21178fbb107201083837ef9e843fdaa53` (`test: verify OPC UA port direction codes`).
- Fresh feature-build regressions: `rtt_opcua` passed 10/10 tests; the maintained OCL OPC UA suite passed 6/6 tests.
- The rebuilt direct client reported `direct OPC UA interface mapping probe passed`; it checked root, event, and nested input/output direction metadata as scalar, read-only OPC UA `Int32` values while retaining the existing data-plane and generated-service checks.
- TaskBrowser reported `add(20, 22) = 42`, `control.scale(10) = 45`, and `control.nested.ping() = true`.
- `mdbook build`, `mdbook test`, and `tools/check-repository-policy.rb` exited 0; root, `rtt_opcua`, and OCL `git diff --check` commands were clean.
- The deployer and direct client resolved `liborocos-rtt-opcua-gnulinux.so` from the refreshed probe prefix. Ctrl-C shutdown of the deployer exited 0 and open62541 reported `still-allocated=0`; port 4842 and matching runtime processes were absent afterward.
- OCL production source did not change. The retained temporary probe, its prefix, build output, and runtime logs remain outside Git.

## Global Constraints

- Keep the existing deterministic `direction` NodeIds unchanged.
- Publish direction as OPC UA built-in `Int32`, scalar, current read only,
  `BaseDataVariableType`, connected with `HasComponent`.
- Publish `RTT::InputPort<T>` and event input ports as code `0`.
- Publish `RTT::OutputPort<T>` as code `1`.
- Interpret direction from the published component's perspective; the
  server-side anti-port does not change this metadata.
- Do not define an `unknown` code. Reject a port that matches neither RTT
  direction interface or ambiguously matches both.
- Require the proxy Variant to be exactly scalar built-in `Int32`.
- Reject legacy strings, other integer widths, floating-point values, arrays,
  and every unknown `Int32` code. Do not convert or guess.
- Preserve all port sample types, `read`/`write` method schemas,
  `FlowStatus`/`WriteStatus` codes, generated port services, sparse categories,
  lifecycle behavior, and transactional publication guarantees.
- Keep OCL production code unchanged; OCL only consumes the generic
  `rtt_opcua` publisher and proxy.
- Do not add a custom OPC UA Enumeration DataType, `MultiStateDiscreteType`,
  `EnumStrings`, localization, selector/filter policy, or SDK behavior.
- Install the shared enum header through the existing recursive
  `include/rtt` install rule. It is transport metadata and needs no RTT typekit
  or transport registration.
- Put feature build and install libraries before `/home/liufang/.orocos` in
  every test loader path. Never stage `build/`, `orocos.log`, or temporary probe
  output in Git.
- Commit `rtt_opcua`, OCL, and root documentation changes in their respective
  repositories.

## File Structure

- Create `toolchain/tools/rtt_opcua/include/rtt/opcua/port_direction.hpp`:
  own the public enum and its fixed `std::int32_t` codes.
- Modify `toolchain/tools/rtt_opcua/tests/foundation_test.cpp`: lock the public
  enum's underlying type and values.
- Modify `toolchain/tools/rtt_opcua/src/object_model.cpp`: classify ports,
  reject invalid direction, and publish a dedicated scalar `Int32` metadata
  Variable.
- Modify `toolchain/tools/rtt_opcua/src/client_session.hpp`: replace the
  duplicate private direction enum with the shared public enum.
- Modify `toolchain/tools/rtt_opcua/src/client_session.cpp`: decode and validate
  exact scalar `Int32` direction metadata.
- Modify `toolchain/tools/rtt_opcua/src/remote_port.cpp`: make remote port
  construction and pumping consume `PortDirection`.
- Modify `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`: prove input,
  event-input, output, nested-service, read-only, and invalid-RTT-port behavior.
- Modify `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`: prove
  positive reconstruction and strict rejection of all legacy or malformed
  direction representations.
- Modify `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`: prove
  the deployer publishes integer direction values while its proxy continues to
  move port samples.
- Modify outside Git
  `/tmp/rtt-opcua-interface-probe.7Ym4Ma/interface_probe_client.cpp`: assert
  integer direction metadata for root, event, and nested service ports.
- Modify `docs/src/opcua-port-direction-protocol-plan.md`: record final commit
  hashes and fresh verification evidence after implementation.

---

### Task 1: Install The Shared Port-Direction Contract

**Files:**

- Create:
  `toolchain/tools/rtt_opcua/include/rtt/opcua/port_direction.hpp`
- Modify: `toolchain/tools/rtt_opcua/tests/foundation_test.cpp:1-13`
- Modify: `toolchain/tools/rtt_opcua/tests/foundation_test.cpp:14-84`

**Interfaces:**

- Produces: `RTT::opcua::PortDirection : std::int32_t` with
  `input = 0` and `output = 1`.
- Produces: installed header
  `install/include/orocos/rtt/opcua/port_direction.hpp`.
- Consumes: no RTT typekit, sample codec, or OPC UA custom datatype.

- [x] **Step 1: Add the failing public-contract test**

  Add these includes to `tests/foundation_test.cpp`:

  ```cpp
  #include <rtt/opcua/port_direction.hpp>

  #include <cstdint>
  #include <type_traits>
  ```

  Add this test after `node_paths_never_embed_unescaped_names`:

  ```cpp
  BOOST_AUTO_TEST_CASE(port_direction_codes_are_stable) {
    using RTT::opcua::PortDirection;

    static_assert(
        std::is_same_v<std::underlying_type_t<PortDirection>, std::int32_t>);
    BOOST_TEST(static_cast<std::int32_t>(PortDirection::input) == 0);
    BOOST_TEST(static_cast<std::int32_t>(PortDirection::output) == 1);
  }
  ```

- [x] **Step 2: Build to verify RED**

  Run:

  ```bash
  feature_root=/home/liufang/MetaNC/rock-orocos/.worktrees/opcua-interface-mapping
  base_prefix=/home/liufang/.orocos/toolchain
  export LD_LIBRARY_PATH="$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/install/lib:$base_prefix/lib"

  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2 \
    --target rtt_opcua_foundation_test
  ```

  Expected: compilation fails because
  `rtt/opcua/port_direction.hpp` does not exist.

- [x] **Step 3: Add the minimal public enum header**

  Create `include/rtt/opcua/port_direction.hpp` with exactly:

  ```cpp
  #pragma once

  #include <cstdint>

  namespace RTT::opcua {

  enum class PortDirection : std::int32_t {
    input = 0,
    output = 1,
  };

  } // namespace RTT::opcua
  ```

  Do not add conversion functions, labels, an `unknown` member, or RTT type
  registration.

- [x] **Step 4: Build and run the focused test to verify GREEN**

  Run:

  ```bash
  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2 \
    --target rtt_opcua_foundation_test
  ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
    --output-on-failure -R '^rtt_opcua_foundation_test$'
  ```

  Expected: the selected test passes and the target builds with
  `RTT_OPCUA_WARNINGS_AS_ERRORS=ON` from the existing CMake cache.

- [x] **Step 5: Install and verify the public header**

  Run:

  ```bash
  cmake --install "$feature_root/toolchain/tools/rtt_opcua/build"
  test -f "$feature_root/install/include/orocos/rtt/opcua/port_direction.hpp"
  rg -n 'enum class PortDirection|input = 0|output = 1' \
    "$feature_root/install/include/orocos/rtt/opcua/port_direction.hpp"
  ```

  Expected: all commands exit `0`; the installed header contains the same two
  fixed codes.

- [x] **Step 6: Commit the shared contract in `rtt_opcua`**

  Run:

  ```bash
  git -C "$feature_root/toolchain/tools/rtt_opcua" diff --check
  git -C "$feature_root/toolchain/tools/rtt_opcua" add \
    include/rtt/opcua/port_direction.hpp tests/foundation_test.cpp
  git -C "$feature_root/toolchain/tools/rtt_opcua" commit \
    -m "feat: define OPC UA port direction codes"
  ```

  Expected: the commit contains only the new header and its contract test;
  untracked `build/` remains unstaged.

### Task 2: Publish And Consume Strict Scalar Int32 Direction

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp:1-30`
- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp:536-582`
- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp:1133-1196`
- Modify: `toolchain/tools/rtt_opcua/src/client_session.hpp:1-68`
- Modify: `toolchain/tools/rtt_opcua/src/client_session.cpp:1-128`
- Modify: `toolchain/tools/rtt_opcua/src/client_session.cpp:859-1006`
- Modify: `toolchain/tools/rtt_opcua/src/remote_port.cpp:1-328`
- Test: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`
- Test: `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`

**Interfaces:**

- Consumes: `PortDirection` from Task 1 and RTT
  `InputPortInterface`/`OutputPortInterface` runtime classification.
- Produces: `NodeSpec portDirectionSpec(const std::string &port_path,
  PortDirection direction)` with built-in scalar `Int32` and read-only access.
- Produces: strict `readPortDirection(...)` decoding that accepts only codes
  `0` and `1` from an exact scalar built-in `Int32` Variant.
- Preserves: `RemotePortDescription::direction`, but changes its type from the
  removed private `RemotePortDirection` to public `PortDirection`.

- [x] **Step 1: Add server-model assertions for exact integer metadata**

  Include the shared header in `tests/object_model_test.cpp`:

  ```cpp
  #include <rtt/opcua/port_direction.hpp>
  ```

  Add this helper after `requireMissingNode`:

  ```cpp
  void requirePortDirection(::opcua::Client &client,
                            const ::opcua::NodeId &parent_id,
                            const ::opcua::NodeId &id,
                            RTT::opcua::PortDirection expected) {
    const auto value = ::opcua::services::readValue(client, id);
    BOOST_REQUIRE(value);
    BOOST_TEST(value.value().isScalar());
    BOOST_TEST(value.value().isType(
        ::opcua::NodeId(::opcua::DataTypeId::Int32)));
    BOOST_TEST(value.value().to<std::int32_t>() ==
               static_cast<std::int32_t>(expected));

    const auto data_type = ::opcua::services::readDataType(client, id);
    const auto node_class = ::opcua::services::readNodeClass(client, id);
    const auto value_rank = ::opcua::services::readValueRank(client, id);
    const auto access = ::opcua::services::readAccessLevel(client, id);
    const auto user_access =
        ::opcua::services::readUserAccessLevel(client, id);
    BOOST_REQUIRE(data_type);
    BOOST_REQUIRE(node_class);
    BOOST_REQUIRE(value_rank);
    BOOST_REQUIRE(access);
    BOOST_REQUIRE(user_access);
    BOOST_CHECK(data_type.value() ==
                ::opcua::NodeId(::opcua::DataTypeId::Int32));
    BOOST_CHECK(node_class.value() == ::opcua::NodeClass::Variable);
    BOOST_TEST(value_rank.value() == ::opcua::ValueRank::Scalar);
    BOOST_TEST(access.value().allOf(::opcua::AccessLevel::CurrentRead));
    BOOST_TEST(access.value().noneOf(::opcua::AccessLevel::CurrentWrite));
    BOOST_TEST(user_access.value().allOf(::opcua::AccessLevel::CurrentRead));
    BOOST_TEST(
        user_access.value().noneOf(::opcua::AccessLevel::CurrentWrite));

    BOOST_TEST(::opcua::services::writeValue(
                   client, id,
                   ::opcua::Variant(static_cast<std::int32_t>(expected))) ==
               UA_STATUSCODE_BADNOTWRITABLE);

    const ::opcua::BrowseDescription parent_browse(
        id, ::opcua::BrowseDirection::Inverse,
        ::opcua::ReferenceTypeId::HasComponent, false,
        ::opcua::NodeClass::Object, ::opcua::BrowseResultMask::All);
    const auto parents = ::opcua::services::browseAll(client, parent_browse);
    BOOST_REQUIRE(parents);
    BOOST_TEST(std::ranges::any_of(
        parents.value(), [&](const auto &reference) {
          return reference.nodeId().isLocal() &&
                 reference.nodeId().nodeId() == parent_id;
        }));

    const ::opcua::BrowseDescription type_browse(
        id, ::opcua::BrowseDirection::Forward,
        ::opcua::ReferenceTypeId::HasTypeDefinition, false,
        ::opcua::NodeClass::VariableType, ::opcua::BrowseResultMask::All);
    const auto type_definitions =
        ::opcua::services::browseAll(client, type_browse);
    BOOST_REQUIRE(type_definitions);
    BOOST_TEST(std::ranges::any_of(
        type_definitions.value(), [](const auto &reference) {
          return reference.nodeId().isLocal() &&
                 reference.nodeId().nodeId() ==
                     ::opcua::NodeId(
                         ::opcua::VariableTypeId::BaseDataVariableType);
        }));
  }
  ```

  In `publish_component_creates_one_complete_static_snapshot`, create concrete
  port Object and direction NodeIds for `Feedback`, `Command`, `Trigger`,
  `MotionFeedback`, and `MotionCommand`. Replace the string assertions with:

  ```cpp
  requirePortDirection(client, feedback_id, feedback_direction_id,
                       RTT::opcua::PortDirection::output);
  requirePortDirection(client, command_id, command_direction_id,
                       RTT::opcua::PortDirection::input);
  requirePortDirection(client, trigger_id, trigger_direction_id,
                       RTT::opcua::PortDirection::input);
  requirePortDirection(client, nested_output_id,
                       motion_feedback_direction_id,
                       RTT::opcua::PortDirection::output);
  requirePortDirection(client, nested_input_id, motion_command_direction_id,
                       RTT::opcua::PortDirection::input);
  ```

  This proves root input/output, event input, and nested-service input/output
  use one contract.

- [x] **Step 2: Add strict publisher rejection for a directionless RTT port**

  Add these includes to `tests/object_model_test.cpp`:

  ```cpp
  #include <rtt/base/PortInterface.hpp>
  #include <rtt/internal/SharedConnection.hpp>
  ```

  Add this complete local test double before the test cases:

  ```cpp
  class DirectionlessPort final : public RTT::base::PortInterface {
  public:
    explicit DirectionlessPort(const std::string &name)
        : RTT::base::PortInterface(name) {}

    bool connected() const override { return false; }
    const RTT::types::TypeInfo *getTypeInfo() const override {
      return RTT::types::Types()->type("Int32");
    }
    void disconnect() override {}
    bool disconnect(RTT::base::PortInterface *) override { return false; }
    RTT::base::PortInterface *clone() const override {
      return new DirectionlessPort(getName());
    }
    RTT::base::PortInterface *antiClone() const override {
      return new DirectionlessPort(getName());
    }
    bool connectTo(RTT::base::PortInterface *,
                   const RTT::ConnPolicy &) override {
      return false;
    }
    bool connectTo(RTT::base::PortInterface *) override { return false; }
    bool createStream(const RTT::ConnPolicy &) override { return false; }
    bool createConnection(
        RTT::internal::SharedConnectionBase::shared_ptr,
        const RTT::ConnPolicy &) override {
      return false;
    }
    bool addConnection(RTT::internal::ConnID *,
                       RTT::base::ChannelElementBase::shared_ptr,
                       const RTT::ConnPolicy &) override {
      return false;
    }
    RTT::base::ChannelElementBase *getEndpoint() const override {
      return nullptr;
    }
  };

  class DirectionlessPortComponent final : public RTT::TaskContext {
  public:
    DirectionlessPortComponent()
        : RTT::TaskContext("directionless-port-component"),
          directionless("Directionless") {
      ports()->addLocalPort(directionless);
    }

    ~DirectionlessPortComponent() override {
      ports()->removeLocalPort(directionless.getName());
    }

    DirectionlessPort directionless;
  };
  ```

  Add this test:

  ```cpp
  BOOST_FIXTURE_TEST_CASE(directionless_port_rejects_the_whole_component,
                          CanonicalTypesFixture) {
    RTT::opcua::ServerOptions server_options;
    server_options.port = unusedLoopbackPort();
    RTT::opcua::Server server(server_options);
    std::string error;
    BOOST_REQUIRE_MESSAGE(server.start(&error), error);

    DirectionlessPortComponent component;
    RTT::opcua::ObjectModel model(server);
    std::vector<RTT::opcua::UnsupportedResource> diagnostics;
    BOOST_TEST(!model.publishComponent(component, &error, &diagnostics));
    BOOST_REQUIRE_EQUAL(diagnostics.size(), 1U);
    BOOST_TEST(diagnostics.front().path == "Directionless");
    BOOST_TEST(diagnostics.front().kind == "port");
    BOOST_TEST(diagnostics.front().type_name == "Int32");
    BOOST_TEST(diagnostics.front().reason ==
               "matches neither RTT input nor output interface");
    BOOST_TEST(model.componentCount() == 0U);
    BOOST_TEST(model.revision() == 0U);

    ::opcua::Client client;
    client.connect(server.endpointUrl());
    requireMissingNode(
        client, modelNodeId(*server.namespaceIndex(),
                            {"components", component.getName()}));
    client.disconnect();
    server.stop();
  }
  ```

- [x] **Step 3: Add proxy mutation helpers for malformed direction metadata**

  Include the shared header in `tests/task_context_proxy_test.cpp`:

  ```cpp
  #include <rtt/opcua/port_direction.hpp>
  ```

  Add this helper after `removeNodeIfPresent`:

  ```cpp
  void replaceDirectionMetadata(
      ::opcua::Server &server, std::uint16_t namespace_index,
      std::string_view component_name, std::string_view port_name,
      ::opcua::Variant value, ::opcua::NodeId data_type,
      ::opcua::ValueRank value_rank) {
    const auto port_id = modelNodeId(
        namespace_index,
        {"components", component_name, "ports", port_name});
    const auto direction_id = modelNodeId(
        namespace_index,
        {"components", component_name, "ports", port_name, "direction"});
    bool replaced = false;
    std::string error;
    BOOST_REQUIRE_MESSAGE(
        server.invoke(
            [&, value = std::move(value), data_type = std::move(data_type),
             value_rank](
                ::opcua::Server &native) mutable {
              const auto deleted =
                  ::opcua::services::deleteNode(native, direction_id, true);
              if (!deleted.isGood()) {
                throw ::opcua::BadStatus(deleted);
              }
              ::opcua::VariableAttributes attributes;
              attributes.setDisplayName(
                  ::opcua::LocalizedText("en-US", "direction"));
              attributes.setDescription(::opcua::LocalizedText(
                  "en-US", "RTT port direction."));
              attributes.setValue(std::move(value));
              attributes.setDataType(data_type);
              attributes.setValueRank(value_rank);
              if (value_rank == ::opcua::ValueRank::OneDimension) {
                attributes.setArrayDimensions({0U});
              }
              attributes.setAccessLevel(::opcua::AccessLevel::CurrentRead);
              attributes.setUserAccessLevel(
                  ::opcua::AccessLevel::CurrentRead);
              replaced = static_cast<bool>(::opcua::services::addVariable(
                  native, port_id, direction_id, "direction", attributes,
                  ::opcua::VariableTypeId::BaseDataVariableType,
                  ::opcua::ReferenceTypeId::HasComponent));
            },
            std::chrono::seconds(1), &error),
        error);
    BOOST_REQUIRE(replaced);
  }
  ```

- [x] **Step 4: Add proxy tests for exact decoding and rejection**

  The existing main proxy test already requires `Feedback` to reconstruct as
  an `OutputPortInterface` and `Command` as an `InputPortInterface`; preserve
  those positive assertions.

  Add this malformed-schema test after
  `proxy_rejects_missing_metadata_inside_a_present_category`:

  ```cpp
  BOOST_FIXTURE_TEST_CASE(proxy_rejects_noncanonical_port_direction_metadata,
                          CanonicalTypesFixture) {
    const auto require_rejected =
        [](::opcua::Variant value, ::opcua::NodeId data_type,
           ::opcua::ValueRank value_rank, std::string_view port_name,
           std::string_view expected_error) {
          RTT::opcua::ServerOptions server_options;
          server_options.port = unusedLoopbackPort();
          RTT::opcua::Server server(server_options);
          std::string error;
          BOOST_REQUIRE_MESSAGE(server.start(&error), error);

          ProxyTarget target;
          RTT::opcua::ObjectModel model(server);
          BOOST_REQUIRE_MESSAGE(model.publishComponent(target, &error), error);
          replaceDirectionMetadata(
              server, *server.namespaceIndex(), target.getName(), port_name,
              std::move(value), std::move(data_type), value_rank);

          RTT::opcua::TaskContextProxyOptions options;
          options.request_timeout = std::chrono::milliseconds(500);
          auto proxy = RTT::opcua::TaskContextProxy::create(
              server.endpointUrl(), target.getName(), options, &error);
          BOOST_TEST(proxy == nullptr);
          BOOST_TEST(error.find(expected_error) != std::string::npos);
          server.stop();
        };

    require_rejected(::opcua::Variant(std::string("input")),
                     ::opcua::NodeId(::opcua::DataTypeId::String),
                     ::opcua::ValueRank::Scalar, "Command",
                     "expected scalar Int32");
    require_rejected(::opcua::Variant(std::string("output")),
                     ::opcua::NodeId(::opcua::DataTypeId::String),
                     ::opcua::ValueRank::Scalar, "Feedback",
                     "expected scalar Int32");
    require_rejected(::opcua::Variant(std::uint32_t{1U}),
                     ::opcua::NodeId(::opcua::DataTypeId::UInt32),
                     ::opcua::ValueRank::Scalar, "Feedback",
                     "expected scalar Int32");
    require_rejected(::opcua::Variant(1.0),
                     ::opcua::NodeId(::opcua::DataTypeId::Double),
                     ::opcua::ValueRank::Scalar, "Feedback",
                     "expected scalar Int32");
    require_rejected(::opcua::Variant(std::vector<std::int32_t>{1}),
                     ::opcua::NodeId(::opcua::DataTypeId::Int32),
                     ::opcua::ValueRank::OneDimension, "Feedback",
                     "expected scalar Int32");
    require_rejected(::opcua::Variant(std::int32_t{7}),
                     ::opcua::NodeId(::opcua::DataTypeId::Int32),
                     ::opcua::ValueRank::Scalar, "Feedback",
                     "remote port 'Feedback' has unsupported direction code 7");
  }
  ```

  Add a separate missing-node test:

  ```cpp
  BOOST_FIXTURE_TEST_CASE(proxy_rejects_missing_port_direction_metadata,
                          CanonicalTypesFixture) {
    RTT::opcua::ServerOptions server_options;
    server_options.port = unusedLoopbackPort();
    RTT::opcua::Server server(server_options);
    std::string error;
    BOOST_REQUIRE_MESSAGE(server.start(&error), error);

    ProxyTarget target;
    RTT::opcua::ObjectModel model(server);
    BOOST_REQUIRE_MESSAGE(model.publishComponent(target, &error), error);
    const auto direction_id = modelNodeId(
        *server.namespaceIndex(),
        {"components", target.getName(), "ports", "Feedback", "direction"});
    BOOST_REQUIRE_MESSAGE(
        server.invoke(
            [&](::opcua::Server &native) {
              const auto status =
                  ::opcua::services::deleteNode(native, direction_id, true);
              if (!status.isGood()) {
                throw ::opcua::BadStatus(status);
              }
            },
            std::chrono::seconds(1), &error),
        error);

    RTT::opcua::TaskContextProxyOptions options;
    options.request_timeout = std::chrono::milliseconds(500);
    auto proxy = RTT::opcua::TaskContextProxy::create(
        server.endpointUrl(), target.getName(), options, &error);
    BOOST_TEST(proxy == nullptr);
    BOOST_TEST(error.find("failed to read RTT port direction metadata") !=
               std::string::npos);
    BOOST_TEST(error.find("BadNodeIdUnknown") != std::string::npos);

    server.stop();
  }
  ```

  Keep the existing missing `type` metadata test unchanged so both metadata
  paths remain covered.

- [x] **Step 5: Run the focused tests to verify RED**

  Run:

  ```bash
  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2 \
    --target rtt_opcua_object_model_test rtt_opcua_task_context_proxy_test
  ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
    --output-on-failure \
    -R '^(rtt_opcua_object_model_test|rtt_opcua_task_context_proxy_test)$'
  ```

  Expected: the object-model test fails because `direction` is still a String;
  the proxy test fails because legacy `"input"` and `"output"` are still
  accepted and strict diagnostic text is not implemented.

- [x] **Step 6: Implement the dedicated publisher `NodeSpec`**

  Include the shared header from `src/object_model.cpp`:

  ```cpp
  #include <rtt/opcua/port_direction.hpp>
  ```

  Add this focused builder beside `staticStringSpec`:

  ```cpp
  NodeSpec portDirectionSpec(const std::string &port_path,
                             PortDirection direction) {
    NodeSpec spec;
    spec.kind = NodeKind::variable;
    spec.parent_path = port_path;
    spec.path = appendNodeSegment(port_path, "direction");
    spec.browse_name = "direction";
    const auto value = static_cast<std::int32_t>(direction);
    spec.fingerprint = "port-direction|" + spec.parent_path + "|" +
                       spec.browse_name + "|" + std::to_string(value);
    spec.create = [path = spec.path, parent = spec.parent_path,
                   value](::opcua::Server &server,
                          std::uint16_t namespace_index, bool *created,
                          std::string *error) {
      ::opcua::VariableAttributes attributes;
      attributes.setDisplayName(
          ::opcua::LocalizedText("en-US", "direction"));
      attributes.setDescription(
          ::opcua::LocalizedText("en-US", "RTT port direction."));
      attributes.setValue(::opcua::Variant(value));
      attributes.setDataType(::opcua::DataTypeId::Int32);
      attributes.setValueRank(::opcua::ValueRank::Scalar);
      attributes.setAccessLevel(readOnlyAccess());
      attributes.setUserAccessLevel(readOnlyAccess());
      const auto result = ::opcua::services::addVariable(
          server, nodeId(namespace_index, parent),
          nodeId(namespace_index, path), "direction", attributes,
          ::opcua::VariableTypeId::BaseDataVariableType,
          ::opcua::ReferenceTypeId::HasComponent);
      return componentNodeCreated(result, path, created, error);
    };
    return spec;
  }
  ```

  Do not reuse `staticStringSpec` or expose a writable backend for this node.

- [x] **Step 7: Classify direction before publishing each port**

  In `appendPortNodes`, immediately after calculating `is_input` and
  `is_output`, reject ambiguous classification before codec validation:

  ```cpp
  if (is_input == is_output) {
    appendUnsupported(
        unsupported, state->component_name,
        appendDiagnosticSegment(diagnostic_path, name), "port",
        typeName(type),
        is_input ? "matches both RTT input and output interfaces"
                 : "matches neither RTT input nor output interface");
    continue;
  }
  const PortDirection direction =
      is_input ? PortDirection::input : PortDirection::output;
  ```

  Delete the `std::string direction = "unknown"` block and replace its
  `staticStringSpec` insertion with:

  ```cpp
  insertNode(nodes, portDirectionSpec(port_path, direction));
  ```

  Leave the existing input `write`, output `read`, retained output `value`,
  and unsupported sample-codec branches unchanged.

- [x] **Step 8: Make the proxy description use the shared enum**

  In `src/client_session.hpp`, include:

  ```cpp
  #include <rtt/opcua/port_direction.hpp>
  ```

  Delete:

  ```cpp
  enum class RemotePortDirection { input, output };
  ```

  Change the description field to:

  ```cpp
  PortDirection direction{PortDirection::input};
  ```

  Replace every `RemotePortDirection::input` and
  `RemotePortDirection::output` use in `src/client_session.cpp` and
  `src/remote_port.cpp` with `PortDirection::input` and
  `PortDirection::output`. Do not retain a compatibility alias.

- [x] **Step 9: Implement exact scalar Int32 proxy decoding**

  Add this helper beside `readStringValue` in `src/client_session.cpp`:

  ```cpp
  bool readPortDirection(::opcua::Client &client,
                         const ::opcua::NodeId &node_id,
                         std::string_view port_name,
                         PortDirection *direction, std::string *error) {
    const auto result = ::opcua::services::readValue(client, node_id);
    if (!result) {
      assignError(error,
                  statusMessage("failed to read RTT port direction metadata",
                                result.code()));
      return false;
    }

    const ::opcua::Variant &value = result.value();
    if (!value.isScalar() ||
        !value.isType(::opcua::NodeId(::opcua::DataTypeId::Int32))) {
      assignError(error, "remote port '" + std::string(port_name) +
                             "' has invalid direction metadata: expected "
                             "scalar Int32");
      return false;
    }

    const std::int32_t code = value.to<std::int32_t>();
    switch (code) {
    case static_cast<std::int32_t>(PortDirection::input):
      *direction = PortDirection::input;
      return true;
    case static_cast<std::int32_t>(PortDirection::output):
      *direction = PortDirection::output;
      return true;
    default:
      assignError(error, "remote port '" + std::string(port_name) +
                             "' has unsupported direction code " +
                             std::to_string(code));
      return false;
    }
  }
  ```

  In `ClientSession::discoverPorts`, remove the temporary direction String and
  its `"input"`/`"output"` branch. Keep `readStringValue` for `type`, then call:

  ```cpp
  if (!readStringValue(
          *client_,
          ::opcua::NodeId(
              namespace_index_,
              modelPath(component_name, service_path, type_segments)),
          "RTT port type metadata", &port.type_name, &last_error_) ||
      !readPortDirection(
          *client_,
          ::opcua::NodeId(
              namespace_index_,
              modelPath(component_name, service_path, direction_segments)),
          port.name, &port.direction, &last_error_)) {
    assignError(error, last_error_);
    ports.clear();
    return ports;
  }
  ```

  Continue selecting `write` for `PortDirection::input`, `read` for
  `PortDirection::output`, then run the existing method-schema validation.

- [x] **Step 10: Run focused and full `rtt_opcua` suites to verify GREEN**

  Run:

  ```bash
  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2 \
    --target rtt_opcua_object_model_test rtt_opcua_task_context_proxy_test
  ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
    --output-on-failure \
    -R '^(rtt_opcua_object_model_test|rtt_opcua_task_context_proxy_test)$'

  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2
  ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
    --output-on-failure
  ```

  Expected: focused `2/2` and complete `10/10` tests pass. The positive proxy
  test reconstructs both port directions and still transfers samples; all
  malformed metadata cases fail construction with their specified messages.

- [x] **Step 11: Install the matching publisher and proxy together**

  Run:

  ```bash
  cmake --install "$feature_root/toolchain/tools/rtt_opcua/build"
  test -f "$feature_root/install/lib/liborocos-rtt-opcua-gnulinux.so"
  test -f "$feature_root/install/include/orocos/rtt/opcua/port_direction.hpp"
  ```

  Expected: the feature overlay contains the library implementing both sides
  of the revised wire schema and the header defining its codes.

- [x] **Step 12: Commit the protocol revision in `rtt_opcua`**

  Run:

  ```bash
  git -C "$feature_root/toolchain/tools/rtt_opcua" diff --check
  git -C "$feature_root/toolchain/tools/rtt_opcua" add \
    src/object_model.cpp src/client_session.hpp src/client_session.cpp \
    src/remote_port.cpp tests/object_model_test.cpp \
    tests/task_context_proxy_test.cpp
  git -C "$feature_root/toolchain/tools/rtt_opcua" commit \
    -m "feat: map OPC UA port direction as Int32"
  ```

  Expected: publisher, proxy, and their regression tests are one protocol
  commit; `build/` and `orocos.log` remain unstaged.

### Task 3: Verify The Revised Schema Through OCL

**Files:**

- Modify:
  `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp:4-48`
- Modify:
  `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp:109-147`
- Modify:
  `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp:401-560`

**Interfaces:**

- Consumes: the installed `PortDirection` header and matching `rtt_opcua`
  library from Tasks 1 and 2.
- Produces: direct address-space assertions for root input/event/output and
  nested-service input/output direction codes.
- Preserves: all existing `publishComponent`, sparse generated-service, proxy
  reconstruction, and sample-transfer assertions.

- [x] **Step 1: Add a direct OCL direction-contract helper**

  Include:

  ```cpp
  #include <rtt/opcua/port_direction.hpp>
  ```

  Add this helper after `requireMissingNode`:

  ```cpp
  void requirePortDirection(
      ::opcua::Client &client, std::uint16_t namespace_index,
      std::initializer_list<std::string_view> segments,
      RTT::opcua::PortDirection expected) {
    const auto id = modelNodeId(namespace_index, segments);
    const auto value = ::opcua::services::readValue(client, id);
    BOOST_REQUIRE(value);
    BOOST_TEST(value.value().isScalar());
    BOOST_TEST(value.value().isType(
        ::opcua::NodeId(::opcua::DataTypeId::Int32)));
    BOOST_TEST(value.value().to<std::int32_t>() ==
               static_cast<std::int32_t>(expected));
  }
  ```

- [x] **Step 2: Assert every representative deployed port direction**

  In `strict_publication_is_static_and_idempotent`, after connecting the
  direct client and obtaining `namespace_index`, add:

  ```cpp
  requirePortDirection(
      client, namespace_index,
      {"components", "CompleteMapping", "ports", "Command", "direction"},
      RTT::opcua::PortDirection::input);
  requirePortDirection(
      client, namespace_index,
      {"components", "CompleteMapping", "ports", "Trigger", "direction"},
      RTT::opcua::PortDirection::input);
  requirePortDirection(
      client, namespace_index,
      {"components", "CompleteMapping", "ports", "Feedback", "direction"},
      RTT::opcua::PortDirection::output);
  requirePortDirection(
      client, namespace_index,
      {"components", "CompleteMapping", "services", "control", "ports",
       "ServiceCommand", "direction"},
      RTT::opcua::PortDirection::input);
  requirePortDirection(
      client, namespace_index,
      {"components", "CompleteMapping", "services", "control", "ports",
       "ServiceFeedback", "direction"},
      RTT::opcua::PortDirection::output);
  ```

  Leave the following existing assertions intact: sparse generated port
  services, `TaskContextProxy` input/output RTT classes, `Command` sample
  delivery, `Feedback` sample delivery, nested service port delivery, and
  generated service operations.

- [x] **Step 3: Reconfigure OCL against the feature overlay**

  Run:

  ```bash
  PKG_CONFIG_PATH="$feature_root/install/lib/pkgconfig:$base_prefix/lib/pkgconfig" \
    cmake -S "$feature_root/toolchain/tools/ocl" \
      -B "$feature_root/toolchain/tools/ocl/build-overlay" \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_INSTALL_PREFIX="$feature_root/install" \
      -DCMAKE_PREFIX_PATH="$feature_root/install;$base_prefix" \
      -DBUILD_TESTING=ON -DBUILD_TESTS=ON -DBUILD_DEPLOYMENT=ON \
      -DBUILD_TASKBROWSER=ON -DBUILD_OPCUA=ON

  rg -n '^RTT_OPCUA_LIBRARY_DIRS:INTERNAL=' \
    "$feature_root/toolchain/tools/ocl/build-overlay/CMakeCache.txt"
  ```

  Expected: `RTT_OPCUA_LIBRARY_DIRS` lists
  `$feature_root/install/lib` before the base prefix.

- [x] **Step 4: Build and run the focused and complete OCL OPC UA suite**

  Run:

  ```bash
  export LD_LIBRARY_PATH="$feature_root/toolchain/tools/ocl/build-overlay/deployment:$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/install/lib:$base_prefix/lib"

  cmake --build "$feature_root/toolchain/tools/ocl/build-overlay" --parallel 2 \
    --target ocl_opcua_deployment_test deployer-opcua ctaskbrowser-opcua
  ctest --test-dir "$feature_root/toolchain/tools/ocl/build-overlay" \
    --output-on-failure \
    -R '^ocl_opcua_deployment_strict_publication_is_static_and_idempotent$'
  ctest --test-dir "$feature_root/toolchain/tools/ocl/build-overlay" \
    --output-on-failure -R '^ocl_opcua_deployment_.*$'
  ```

  Expected: the focused case and all six maintained OCL OPC UA cases pass.
  This task adds consumer acceptance coverage but no OCL production behavior,
  so its first run is expected to be green against the already test-driven
  `rtt_opcua` implementation from Task 2.

- [x] **Step 5: Install and commit OCL acceptance coverage**

  Run:

  ```bash
  cmake --install "$feature_root/toolchain/tools/ocl/build-overlay"
  git -C "$feature_root/toolchain/tools/ocl" diff --check
  git -C "$feature_root/toolchain/tools/ocl" add \
    deployment/tests/opcua_deployment_test.cpp
  git -C "$feature_root/toolchain/tools/ocl" commit \
    -m "test: verify OPC UA port direction codes"
  ```

  Expected: only the OCL acceptance test is committed; OCL deployment
  production sources remain unchanged.

### Task 4: Rebuild The Temporary Probe And Close Verification

**Files:**

- Modify outside Git:
  `/tmp/rtt-opcua-interface-probe.7Ym4Ma/interface_probe_client.cpp`
- Rebuild outside Git: `/tmp/rtt-opcua-interface-probe.7Ym4Ma/build/`
- Refresh outside Git: `/tmp/rtt-opcua-interface-probe.7Ym4Ma/prefix/`
- Modify: `docs/src/opcua-port-direction-protocol-plan.md`

**Interfaces:**

- Consumes: feature-overlay `rtt_opcua` and OCL artifacts from Tasks 2 and 3.
- Produces: direct OPC UA evidence for numeric direction metadata and preserved
  data-plane/generated-service behavior.
- Produces: TaskBrowser evidence that the remote object/service surface remains
  usable.

- [x] **Step 1: Make the direct probe require integer direction metadata**

  Include the shared contract in
  `/tmp/rtt-opcua-interface-probe.7Ym4Ma/interface_probe_client.cpp`:

  ```cpp
  #include <rtt/opcua/port_direction.hpp>
  ```

  Add this helper beside the existing `readValue` helper:

  ```cpp
  void requirePortDirection(::opcua::Client &client,
                            const ::opcua::NodeId &id,
                            RTT::opcua::PortDirection expected,
                            std::string_view label) {
    const auto result = ::opcua::services::readValue(client, id);
    require(static_cast<bool>(result),
            "failed to read OPC UA direction: " + std::string(label));
    require(result.value().isScalar(),
            "direction is not scalar: " + std::string(label));
    require(result.value().isType(
                ::opcua::NodeId(::opcua::DataTypeId::Int32)),
            "direction is not Int32: " + std::string(label));
    require(result.value().to<std::int32_t>() ==
                static_cast<std::int32_t>(expected),
            "unexpected direction code: " + std::string(label));
    const auto access = ::opcua::services::readUserAccessLevel(client, id);
    require(access &&
                access.value().allOf(::opcua::AccessLevel::CurrentRead) &&
                access.value().noneOf(::opcua::AccessLevel::CurrentWrite),
            "direction is not read only: " + std::string(label));
  }
  ```

  In `verifyInputPort`, replace the String comparison with:

  ```cpp
  requirePortDirection(client, node(ns, direction_path),
                       RTT::opcua::PortDirection::input,
                       std::string(name) + ".direction");
  ```

  In `verifyTrigger`, replace the String comparison with:

  ```cpp
  requirePortDirection(
      client,
      node(ns, {"components", "interface_probe", "ports", "trigger",
                "direction"}),
      RTT::opcua::PortDirection::input, "trigger.direction");
  ```

  In `verifyOutputPort`, replace the String comparison with:

  ```cpp
  requirePortDirection(client, node(ns, direction_path),
                       RTT::opcua::PortDirection::output,
                       std::string(name) + ".direction");
  ```

  Existing calls exercise root input, event input, root output, nested-service
  input, and nested-service output. Preserve every operation, value,
  data-plane, generated-port-service, and sparse-category check.

- [x] **Step 2: Refresh the probe overlay and rebuild**

  Run:

  ```bash
  probe_root=/tmp/rtt-opcua-interface-probe.7Ym4Ma

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

  Expected: the probe client compiles against the installed public
  `PortDirection` header and links successfully.

- [x] **Step 3: Confirm environment-matched runtime resolution**

  Run:

  ```bash
  probe_runtime="$probe_root/prefix/lib:$probe_root/prefix/lib/orocos/gnulinux/ocl:$probe_root/prefix/lib/orocos/gnulinux/ocl/types:$probe_root/prefix/lib/orocos/gnulinux/ocl/plugins:$probe_root/prefix/lib/orocos/gnulinux/rtt_opcua/plugins:$base_prefix/lib"

  LD_LIBRARY_PATH="$probe_runtime" \
    ldd "$probe_root/prefix/bin/deployer-opcua-gnulinux" \
      | rg "$probe_root/prefix"
  LD_LIBRARY_PATH="$probe_runtime" \
    ldd "$probe_root/prefix/bin/interface-probe-client" \
      | rg "$probe_root/prefix"
  ```

  Expected: both commands show probe-prefix libraries, including the revised
  `orocos-rtt-opcua` implementation.

- [x] **Step 4: Run the deployer and both clients**

  In terminal one:

  ```bash
  cd /tmp/rtt-opcua-interface-probe.7Ym4Ma
  ./run-deployer.sh 4842
  ```

  In terminal two:

  ```bash
  cd /tmp/rtt-opcua-interface-probe.7Ym4Ma
  ./run-client.sh opc.tcp://127.0.0.1:4842/rtt
  ./run-taskbrowser.sh opc.tcp://127.0.0.1:4842/rtt
  ```

  Expected direct output:

  ```text
  direct OPC UA interface mapping probe passed
  ```

  Expected TaskBrowser results remain:

  ```text
  add(20, 22) = 42
  control.scale(10) = 45
  control.nested.ping() = true
  ```

  Stop the deployer with `Ctrl-C` only after both clients exit.

- [x] **Step 5: Run fresh full regression and repository checks**

  Run:

  ```bash
  export LD_LIBRARY_PATH="$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/install/lib:$base_prefix/lib"
  cmake --build "$feature_root/toolchain/tools/rtt_opcua/build" --parallel 2
  ctest --test-dir "$feature_root/toolchain/tools/rtt_opcua/build" \
    --output-on-failure

  export LD_LIBRARY_PATH="$feature_root/toolchain/tools/ocl/build-overlay/deployment:$feature_root/toolchain/tools/rtt_opcua/build:$feature_root/install/lib:$base_prefix/lib"
  cmake --build "$feature_root/toolchain/tools/ocl/build-overlay" --parallel 2 \
    --target ocl_opcua_deployment_test deployer-opcua ctaskbrowser-opcua
  ctest --test-dir "$feature_root/toolchain/tools/ocl/build-overlay" \
    --output-on-failure -R '^ocl_opcua_deployment_.*$'

  verify_dir=$(mktemp -d /tmp/orocos-opcua-port-direction-verify.XXXXXX)
  mdbook build "$feature_root/docs" --dest-dir "$verify_dir/book"
  mdbook test "$feature_root/docs"
  ruby "$feature_root/tools/check-repository-policy.rb"

  git -C "$feature_root" diff --check
  git -C "$feature_root/toolchain/tools/rtt_opcua" diff --check
  git -C "$feature_root/toolchain/tools/ocl" diff --check
  ```

  Expected: `rtt_opcua` passes `10/10`, OCL passes all six maintained OPC UA
  cases, mdBook and policy checks exit `0`, and all three diff checks are
  clean.

- [x] **Step 6: Record completion evidence and commit root documentation**

  Add a `## Completion Evidence` section near the top of this chapter. Record:

  - the two exact `rtt_opcua` commit hashes and subjects from Tasks 1 and 2;
  - the exact OCL commit hash and subject from Task 3;
  - the fresh `rtt_opcua` and OCL test counts from Step 5;
  - the direct probe success line and three TaskBrowser results from Step 4;
  - the mdBook, repository-policy, and diff-check results; and
  - confirmation that no OCL production source changed and no probe artifact
    entered Git.

  Mark each completed checkbox only after its command has succeeded, then run:

  ```bash
  git -C "$feature_root" add \
    docs/src/opcua-port-direction-protocol-plan.md
  git -C "$feature_root" diff --cached --check
  git -C "$feature_root" commit \
    -m "docs: record OPC UA port direction verification"
  ```

  Expected: the root commit contains only final plan status and evidence. The
  design chapter remains the normative contract.
