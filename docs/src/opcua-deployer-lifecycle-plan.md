# OPC UA Deployer Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `deployer-opcua` start only through the explicit local
`opcua.start()` API, publish complete components strictly, map
`RTT::ConnPolicy` generically, and expose RTT ports as best-effort latest-value
OPC UA surfaces.

**Architecture:** `rtt_opcua` owns the generic `ConnPolicy` datatype and codec,
strict component snapshots, transactional address-space reconciliation, and
component leases. Its port bridge uses lock-free RTT DATA connections and a
50 ms default proxy poll interval, so supervisory clients see the newest value
rather than a queued backlog. OCL owns deployment lifecycle state,
component-name resolution, failed-publication diagnostics, and the local
service API. The executable creates a local Deployer and TaskBrowser with the
endpoint stopped; an installed external fixture proves the import, load,
start, publish, and remote browse flow without MetaNC dependencies.

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
  implementing or testing. Existing package build trees may be used only for
  focused red/green compilation without installation; every authoritative
  clean build, install prefix, isolated `HOME`, log, cache, and ready file must
  be below a new `/tmp` directory.
- Keep open62541 at `v1.4.15` and open62541pp at `v0.21.2`.
- Before installed-prefix verification, set
  `OROCOS_OPCUA_DEPENDENCY_PREFIX` to the existing open62541/open62541pp
  dependency prefix below `/tmp`; the verifier rejects any other location.
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
- RTT OPC UA ports are best-effort latest-value transport: use lock-free DATA,
  default proxy polling to 50 ms, retain pending client writes until
  `WriteSuccess`, and do not claim queued, lossless, exactly-once, PubSub, or
  deterministic-control semantics.
- Task numbers in this document are local lifecycle implementation tasks; they
  are not the MetaNC migration steps 9 through 13, which remain out of scope.
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

The codec portion of the test must include:

```cpp
const auto registry = makeRegistry();
const RTT::opcua::TypeCodec *codec =
    registry->codecForTypeName("ConnPolicy");
BOOST_REQUIRE(codec != nullptr);
BOOST_CHECK(codec->dataTypeNodeId() ==
            ::opcua::NodeId(1, "types/ConnPolicy"));
RTT::internal::ValueDataSource<RTT::ConnPolicy>::shared_ptr source =
    new RTT::internal::ValueDataSource<RTT::ConnPolicy>(expected);
::opcua::Variant encoded;
BOOST_REQUIRE(codec->toVariant(source, &encoded));
const auto decoded = codec->makeDataSource(encoded);
const auto typed = boost::dynamic_pointer_cast<
    RTT::internal::DataSource<RTT::ConnPolicy>>(decoded);
BOOST_REQUIRE(typed);
checkConnPolicy(typed->get(), expected);
```

Define this helper in the test's anonymous namespace:

```cpp
void checkConnPolicy(const RTT::ConnPolicy &actual,
                     const RTT::ConnPolicy &expected) {
  BOOST_TEST(actual.type == expected.type);
  BOOST_TEST(actual.size == expected.size);
  BOOST_TEST(actual.lock_policy == expected.lock_policy);
  BOOST_TEST(actual.init == expected.init);
  BOOST_TEST(actual.pull == expected.pull);
  BOOST_TEST(actual.buffer_policy == expected.buffer_policy);
  BOOST_TEST(actual.max_threads == expected.max_threads);
  BOOST_TEST(actual.mandatory == expected.mandatory);
  BOOST_TEST(actual.transport == expected.transport);
  BOOST_TEST(actual.data_size == expected.data_size);
  BOOST_TEST(actual.name_id == expected.name_id);
}
```

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

```cpp
DataTypeProvider makeConnPolicyProvider() {
  CustomDataTypeDefinition definition;
  definition.name = "ConnPolicy";
  definition.id = connPolicyDataTypeId();
  definition.schema_fingerprint = "rtt-opcua/ConnPolicy/v1";
  definition.materialize = [](const DataTypeFactoryContext &context) {
    return ::opcua::DataTypeBuilder<ConnPolicyWire>::createStructure(
               "ConnPolicy", context.nodeId(connPolicyDataTypeId()),
               {context.namespaceIndex("urn:orocos:rtt"),
                "encodings/ConnPolicy/Binary"})
        .addField<&ConnPolicyWire::type>("type")
        .addField<&ConnPolicyWire::size>("size")
        .addField<&ConnPolicyWire::lock_policy>("lock_policy")
        .addField<&ConnPolicyWire::init>("init")
        .addField<&ConnPolicyWire::pull>("pull")
        .addField<&ConnPolicyWire::buffer_policy>("buffer_policy")
        .addField<&ConnPolicyWire::max_threads>("max_threads")
        .addField<&ConnPolicyWire::mandatory>("mandatory")
        .addField<&ConnPolicyWire::transport>("transport")
        .addField<&ConnPolicyWire::data_size>("data_size")
        .addField<&ConnPolicyWire::name_id>("name_id")
        .build();
  };
  DataTypeProvider provider;
  provider.name = "rtt-foundation";
  provider.namespace_uri = "urn:orocos:rtt";
  provider.data_types.push_back(std::move(definition));
  return provider;
}
```

`connPolicyDataTypeId()` returns one static `LogicalDataTypeId` containing the
three exact URI/NodeId strings in the Interfaces block.

- [ ] **Step 4: Implement conversion without layout reinterpretation**

Implement dedicated assignable and read-only proxy datasources, a
`ConnPolicyTypeCodec`, and a `ConnPolicyTypeProtocol`, following the external
fixture transport's ownership pattern. Encode by copying all RTT fields into a
`ConnPolicyWire`; decode by copying each wire field back and converting
`name_id` through `std::string_view`. Never cast `RTT::ConnPolicy *` to
`ConnPolicyWire *` because the RTT object owns a `std::string`.

Keep the field conversion explicit:

```cpp
ConnPolicyWire toWire(const RTT::ConnPolicy &policy) {
  return ConnPolicyWire{
      static_cast<std::int32_t>(policy.type),
      static_cast<std::int32_t>(policy.size),
      static_cast<std::int32_t>(policy.lock_policy),
      policy.init,
      policy.pull,
      static_cast<std::int32_t>(policy.buffer_policy),
      static_cast<std::int32_t>(policy.max_threads),
      policy.mandatory,
      static_cast<std::int32_t>(policy.transport),
      static_cast<std::int32_t>(policy.data_size),
      ::opcua::String(policy.name_id),
  };
}

RTT::ConnPolicy fromWire(const ConnPolicyWire &wire) {
  RTT::ConnPolicy policy;
  policy.type = wire.type;
  policy.size = wire.size;
  policy.lock_policy = wire.lock_policy;
  policy.init = wire.init;
  policy.pull = wire.pull;
  policy.buffer_policy = wire.buffer_policy;
  policy.max_threads = wire.max_threads;
  policy.mandatory = wire.mandatory;
  policy.transport = wire.transport;
  policy.data_size = wire.data_size;
  policy.name_id = std::string(std::string_view(wire.name_id));
  return policy;
}
```

Use `rtt-opcua/ConnPolicy/v1` as both the provider schema fingerprint and the
protocol registration fingerprint.

The exported private helper validates the RTT-owned name before making both
idempotent registrations:

```cpp
bool registerConnPolicyProtocol(RTT::types::TypeInfo *type_info,
                                std::string *error) {
  if (type_info == nullptr || type_info->getTypeName() != "ConnPolicy") {
    return fail(error, "invalid OPC UA ConnPolicy protocol registration");
  }
  if (!registerDataTypeProvider(makeConnPolicyProvider(), error)) {
    return false;
  }
  return registerTypeProtocol(
      type_info,
      std::make_unique<ConnPolicyTypeProtocol>(connPolicyDataTypeId()),
      error);
}
```

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

The canonical dispatcher must have this control flow:

```cpp
bool registerCanonicalTypeProtocol(std::string_view type_name,
                                   RTT::types::TypeInfo *type_info,
                                   std::string *error) {
  if (type_name == "ConnPolicy") {
    return registerConnPolicyProtocol(type_info, error);
  }
  if (type_info == nullptr || type_info->getTypeName() != type_name ||
      descriptorForType(type_name) == nullptr) {
    return fail(error, "invalid canonical OPC UA type protocol registration");
  }
  std::lock_guard<std::mutex> lock(registrationMutex());
  return registerTypeProtocolUnlocked(
      type_info, makeCanonicalProtocol(type_name), error);
}

bool registerCanonicalTypeProtocols(std::string *error) {
  for (const TypeDescriptor &descriptor : canonicalTypeDescriptors()) {
    RTT::types::TypeInfo *type_info =
        RTT::types::Types()->type(std::string(descriptor.rtt_name));
    if (!registerCanonicalTypeProtocol(descriptor.rtt_name, type_info, error)) {
      return false;
    }
  }
  return registerConnPolicyProtocol(
      RTT::types::Types()->type("ConnPolicy"), error);
}
```

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
- Add one private first-publication helper so validation and mutation use the
  same snapshot:

```cpp
bool publishSnapshot(const std::shared_ptr<ComponentState> &state,
                     const ComponentSnapshot &snapshot,
                     std::string *error);
```

- Add rejected diagnostics beside the active diagnostic map:

```cpp
std::map<std::string, std::vector<UnsupportedResource>, std::less<>>
    failed_publications;
```

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

The changed test's transaction assertions are:

```cpp
const std::uint64_t revision_before = model.revision();
std::vector<RTT::opcua::UnsupportedResource> diagnostics;
auto registration =
    model.registerComponent(component, &error, &diagnostics);
BOOST_TEST(!registration.has_value());
BOOST_TEST(model.componentCount() == 0U);
BOOST_TEST(model.revision() == revision_before);
BOOST_TEST(diagnostics.size() == 6U);
BOOST_TEST(model.unsupportedResources(component.getName()) == diagnostics,
           boost::test_tools::per_element());
BOOST_TEST(!::opcua::services::readBrowseName(client, component_root_id));
BOOST_TEST(!::opcua::services::readBrowseName(client,
                                              supported_property_id));
```

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

The strict branch must occur before `components.emplace` and `reconcile`:

```cpp
auto state = std::make_shared<ComponentState>(component);
ComponentSnapshot snapshot =
    snapshotComponent(state, component, dispatcher, type_registry,
                      options.port_buffer_size);
if (!snapshot.unsupported.empty()) {
  {
    std::lock_guard<std::mutex> lock(model_mutex);
    failed_publications[state->component_name] = snapshot.unsupported;
  }
  if (unsupported != nullptr) {
    *unsupported = snapshot.unsupported;
  }
  assignError(error, "strict OPC UA publication rejected component '" +
                         state->component_name + "'");
  std::vector<DiagnosticEvent> events;
  events.reserve(snapshot.unsupported.size());
  for (const UnsupportedResource &resource : snapshot.unsupported) {
    events.push_back(DiagnosticEvent{false, resource});
  }
  emitDiagnosticEvents(events);
  return {};
}
```

While holding `registry_mutex`, recheck the component-name collision, insert
the state as a registration reservation, and pass the accepted `snapshot` to
`publishSnapshot()`. On failure erase the reservation and deactivate the
state. This prevents the worker from taking a second, different snapshot
between validation and first publication.

`publishSnapshot()` invokes the server synchronously, takes `model_mutex`,
calls `ensureRoots()`, passes `snapshot.nodes` directly to
`reconcileComponent()`, and advances revision only after that call succeeds:

```cpp
bool component_changed = false;
bool published_snapshot = false;
const bool invoked = server.invoke(
    [this, &state, &snapshot, &component_changed, &published_snapshot,
     error](::opcua::Server &native) {
      std::lock_guard<std::mutex> lock(model_mutex);
      const auto index = server.namespaceIndex();
      if (!index || !ensureRoots(native, *index, error) ||
          !reconcileComponent(native, *index, state.get(), snapshot.nodes,
                              &component_changed, error)) {
        return;
      }
      if (component_changed) {
        advanceRevision(native);
      }
      published_snapshot = true;
    });
if (!invoked && (error == nullptr || error->empty())) {
  assignError(error, "failed to invoke initial OPC UA component publication");
}
return invoked && published_snapshot;
```

Task 3 replaces `reconcileComponent()` internals with transactional rollback;
this helper and its accepted-snapshot boundary remain unchanged.

- [ ] **Step 4: Make diagnostic lookup independent of registration**

Have `ObjectModel::unsupportedResources(name)` consult active candidate
diagnostics first and rejected-publication diagnostics second. Remove rejected
diagnostics when the component is successfully registered or explicitly
unregistered. Do not invent a public diagnostics-clear command.

Use one locked lookup with deterministic precedence:

```cpp
std::vector<UnsupportedResource>
diagnosticsFor(std::string_view component_name) const {
  std::lock_guard<std::mutex> lock(model_mutex);
  const auto active = unsupported.find(component_name);
  if (active != unsupported.end()) {
    return active->second;
  }
  const auto rejected = failed_publications.find(component_name);
  return rejected == failed_publications.end()
             ? std::vector<UnsupportedResource>{}
             : rejected->second;
}
```

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

The failure assertions mirror the strict preflight transaction boundary:

```cpp
const std::uint64_t revision_before = model.revision();
auto registration = model.registerComponent(component, &error);
BOOST_TEST(!registration.has_value());
BOOST_TEST(!error.empty());
BOOST_TEST(model.componentCount() == 0U);
BOOST_TEST(model.revision() == revision_before);
BOOST_TEST(!::opcua::services::readBrowseName(client, component_root_id));
BOOST_TEST(!::opcua::services::readBrowseName(client,
                                              ordinary_property_id));
```

- [ ] **Step 2: Add a last-good runtime candidate test**

Publish a fully supported component and record its revision and a known node.
Add the existing unsupported service at runtime and trigger reconciliation.
Assert the old node set and revision remain, the unsupported candidate nodes
are absent, and diagnostics become queryable. Remove the unsupported service,
reconcile again, and assert diagnostics clear; if the supported node set did
not change, revision remains unchanged.

Expose deterministic mutation helpers on the test component:

```cpp
void addUnsupportedService() {
  BOOST_REQUIRE(provides()->addService(unsupported_service));
}

void removeUnsupportedService() {
  provides()->removeService("unsupported");
}
```

Construct this fixture without adding the service initially; reuse its
existing unsupported operation/property/attribute/port contents.

Use the worker's bounded polling helper and keep the revision assertion around
the diagnostic-only candidate:

```cpp
const std::uint64_t last_good_revision = model.revision();
component.addUnsupportedService();
BOOST_REQUIRE(waitUntil([&] {
  return !model.unsupportedResources(component.getName()).empty();
}));
BOOST_TEST(model.revision() == last_good_revision);
BOOST_TEST(::opcua::services::readBrowseName(client, known_good_node_id));
BOOST_TEST(!::opcua::services::readBrowseName(client,
                                              unsupported_service_node_id));
component.removeUnsupportedService();
BOOST_REQUIRE(waitUntil([&] {
  return model.unsupportedResources(component.getName()).empty();
}));
BOOST_TEST(model.revision() == last_good_revision);
```

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

Use separate result policies rather than a boolean hidden in every caller:

```cpp
bool componentNodeCreated(const ::opcua::Result<::opcua::NodeId> &result,
                          const std::string &path, std::string *error) {
  if (result) {
    return true;
  }
  assignError(error, "failed to create OPC UA component node '" + path +
                         "': " + statusName(result.code()));
  return false;
}

bool sharedRootEnsured(const ::opcua::Result<::opcua::NodeId> &result,
                       const std::string &path, std::string *error) {
  if (result || result.code() == UA_STATUSCODE_BADNODEIDEXISTS) {
    return true;
  }
  assignError(error, "failed to ensure OPC UA root node '" + path +
                         "': " + statusName(result.code()));
  return false;
}
```

Apply `componentNodeCreated` to object, variable, method, and port-bridge node
factories. Use `sharedRootEnsured` only from `ensureRoots()`.

- [ ] **Step 5: Apply and roll back one node diff inside one server invoke**

In `reconcileComponent`, compute these collections before mutating the server:

```text
old nodes to remove or replace, leaf first
candidate nodes to add or replace, parent first
old NodeSpecs needed for rollback, parent first
all candidate paths that may have been partially created, leaf first
```

Take `const NodeMap previous = published[state]` before computing the diff.
Do not erase/insert entries in `published[state]` while applying it. After
`invoked && applied`, assign `published[state] = expected` once and set
`*changed = !old_remove_paths.empty() || !candidate_specs.empty()`; on failure
leave the stored map untouched.

Delete old changed/removed nodes, create new/changed candidate nodes, and only
then replace the stored snapshot and increment revision. On any mutation
failure:

1. delete every affected candidate path, including the path whose creator
   returned failure
2. recreate every removed old NodeSpec parent first
3. retain the old stored snapshot and revision
4. return the original error, appending any rollback error explicitly

Because all mutations occur in one `Server::invoke`, remote clients cannot
observe the intermediate diff.

The mutation portion must follow this shape, where each collection is fully
computed before `Server::invoke`:

```cpp
void appendRollbackError(std::string *error, const std::string &rollback_error,
                         bool restored) {
  if (error == nullptr) {
    return;
  }
  *error += restored ? "; rollback succeeded"
                     : "; rollback failed: " + rollback_error;
}
```

```cpp
bool applied = false;
const bool invoked = server.invoke(
    [this, &old_remove_paths, &candidate_specs, &candidate_cleanup_paths,
     &rollback_specs, &applied, error](::opcua::Server &native_server) {
      std::set<std::string> deleted_old_paths;
      auto restoreOld = [&](const std::set<std::string> &paths,
                            std::string *rollback_error) {
        bool restored = true;
        for (const NodeSpec *old_spec : rollback_specs) {
          if (!paths.contains(old_spec->path)) {
            continue;
          }
          restored = old_spec->create(native_server, namespace_index,
                                      rollback_error) &&
                     restored;
        }
        return restored;
      };

      for (const std::string &path : old_remove_paths) {
        const ::opcua::StatusCode result = ::opcua::services::deleteNode(
            native_server, nodeId(namespace_index, path), true);
        if (result.isBad() && result != UA_STATUSCODE_BADNODEIDUNKNOWN) {
          assignError(error, "failed to delete OPC UA node '" + path +
                                 "': " + statusName(result));
          std::string rollback_error;
          const bool restored =
              restoreOld(deleted_old_paths, &rollback_error);
          appendRollbackError(error, rollback_error, restored);
          return;
        }
        deleted_old_paths.insert(path);
      }
      for (const NodeSpec *spec : candidate_specs) {
        if (!spec->create(native_server, namespace_index, error)) {
          std::string rollback_error;
          const bool removed = deleteNodes(native_server, namespace_index,
                                           candidate_cleanup_paths,
                                           &rollback_error);
          const bool restored =
              restoreOld(deleted_old_paths, &rollback_error) && removed;
          appendRollbackError(error, rollback_error, restored);
          return;
        }
      }
      applied = true;
    });
if (!invoked || !applied) {
  return false;
}
```

`candidate_specs` and `rollback_specs` are parent-first; both path vectors are
leaf-first. `appendRollbackError` preserves the original error and appends
either `rollback succeeded` or the concrete rollback failure.

- [ ] **Step 6: Reject unsupported runtime candidates without node mutation**

When `snapshotComponent()` reports unsupported resources for an active
component, update and emit diagnostic events but skip the node diff and leave
the old snapshot/revision intact. A later supported candidate may replace the
old revision normally.

Do this in the existing reconciliation loop before calling
`reconcileComponent()`:

```cpp
self->updateDiagnostics(state->component_name, expected.unsupported,
                        *diagnostic_events);
if (!expected.unsupported.empty()) {
  continue;
}
```

Diagnostic-only changes do not advance `/rtt/model/revision`; advance it only
after a complete node candidate commits or a published component is removed.

- [ ] **Step 7: Run the complete package suite**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure
```

Expected: all package tests pass. Task 9 repeats the complete maintained graph
from a fresh temporary install under ASan, UBSan, and LSan so this task does not
depend on an implicit prerequisite prefix.

- [ ] **Step 8: Commit atomic reconciliation**

```bash
git -C toolchain/tools/rtt_opcua add \
  src/object_model.cpp tests/object_model_test.cpp
git -C toolchain/tools/rtt_opcua commit \
  -m "fix: reconcile OPC UA components atomically"
```

### Task 4: Make OPC UA Ports Best-Effort Latest-Value

**Files:**

- Modify: `toolchain/tools/rtt_opcua/include/rtt/opcua/task_context_proxy.hpp`
- Modify: `toolchain/tools/rtt_opcua/include/rtt/opcua/object_model.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/port_bridge.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/port_bridge.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`
- Modify: `toolchain/tools/rtt_opcua/README.md`

**Interfaces:**

Change the proxy's default supervisory polling cadence without changing its
public shape:

```cpp
struct TaskContextProxyOptions {
  std::chrono::milliseconds request_timeout{std::chrono::seconds(2)};
  std::chrono::milliseconds port_poll_interval{std::chrono::milliseconds(50)};
};
```

Remove the transport buffer size from `ObjectModelOptions`, and reduce bridge
creation to the inputs that affect its behavior:

```cpp
static std::shared_ptr<PortBridge>
create(RTT::base::PortInterface &port,
       std::shared_ptr<const EndpointTypeRegistry> type_registry,
       std::string *error = nullptr);
```

The OPC UA `read()` and `write(value)` method signatures are unchanged. The
semantic contract becomes best-effort latest-value delivery: intermediate
samples may be replaced, and this transport is neither queued nor lossless.

- [ ] **Step 1: Write failing latest-value output-port assertions**

In
`component_metadata_reconciles_and_registration_guards_lifetime`, replace the
single `Feedback` sample with three writes before the first OPC UA call:

```cpp
BOOST_TEST(feedback.write(4.25) == RTT::WriteSuccess);
BOOST_TEST(feedback.write(5.25) == RTT::WriteSuccess);
BOOST_TEST(feedback.write(6.25) == RTT::WriteSuccess);
const auto feedback_result =
    ::opcua::services::call(client, feedback_id, feedback_read_id, {});
BOOST_REQUIRE(feedback_result.statusCode().isGood());
BOOST_REQUIRE_EQUAL(feedback_result.outputArguments().size(), 2U);
BOOST_TEST(feedback_result.outputArguments()[0].to<std::string>() ==
           "NewData");
BOOST_TEST(feedback_result.outputArguments()[1].to<double>() == 6.25);

const auto feedback_old_result =
    ::opcua::services::call(client, feedback_id, feedback_read_id, {});
BOOST_REQUIRE(feedback_old_result.statusCode().isGood());
BOOST_TEST(feedback_old_result.outputArguments()[0].to<std::string>() ==
           "OldData");
BOOST_TEST(feedback_old_result.outputArguments()[1].to<double>() == 6.25);
```

This proves a real RTT `OutputPort` presents the newest sample on the first
remote read and retains it as `OldData` until another write. The old circular
buffer returns `4.25`, so the test must initially fail.

- [ ] **Step 2: Write failing latest-value input-port assertions**

Keep the wrong-type check, then replace the single valid `Command/write` call
with three good calls before the real component reads its input:

```cpp
for (const std::uint16_t value : {std::uint16_t{71}, std::uint16_t{72},
                                  std::uint16_t{73}}) {
  const std::vector<::opcua::Variant> command_inputs{
      ::opcua::Variant(value)};
  const auto command_result = ::opcua::services::call(
      client, command_id, command_write_id, command_inputs);
  BOOST_REQUIRE(command_result.statusCode().isGood());
  BOOST_REQUIRE_EQUAL(command_result.outputArguments().size(), 1U);
  BOOST_TEST(command_result.outputArguments()[0].to<std::string>() ==
             "WriteSuccess");
}

BOOST_TEST(command.read(commanded_value) == RTT::NewData);
BOOST_TEST(commanded_value == 73U);
```

The old circular buffer exposes `71`, so this half must also fail before the
bridge policy changes.

- [ ] **Step 3: Pin the proxy's default polling cadence in a unit test**

Add this next to the existing invalid-interval case:

```cpp
BOOST_AUTO_TEST_CASE(proxy_port_poll_default_is_supervisory_rate) {
  const RTT::opcua::TaskContextProxyOptions options;
  BOOST_TEST(options.port_poll_interval == std::chrono::milliseconds(50));
}
```

Run both affected binaries:

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel \
  --target rtt_opcua_object_model_test rtt_opcua_task_context_proxy_test
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
  -R '^(rtt_opcua_object_model_test|rtt_opcua_task_context_proxy_test)$'
```

Expected: the object-model case sees the oldest queued values, and the proxy
options case sees `10ms`; both failures demonstrate the old behavior.

- [ ] **Step 4: Change only the default poll interval**

Update `TaskContextProxyOptions::port_poll_interval` to `50ms` and rewrite its
comment as a supervisory sampling contract:

```cpp
// Remote ports are sampled at a supervisory cadence by default. Clients that
// need faster observation may set an explicit positive interval.
std::chrono::milliseconds port_poll_interval{std::chrono::milliseconds(50)};
```

Keep the existing validation for zero and overflowing durations. Keep every
fixture-specific `5ms` or `10ms` setting explicit; those values shorten tests
and do not define the product default.

- [ ] **Step 5: Replace the circular anti-port buffer with RTT `DATA`**

Remove `buffer_size` from the declaration and definition of
`PortBridge::create`. Remove its range check and the now-unused `<limits>` and
`<cstddef>` includes. Preserve the type-codec and `antiClone()` checks, then
connect the port pair with:

```cpp
const RTT::ConnPolicy policy =
    RTT::ConnPolicy::data(RTT::ConnPolicy::LOCK_FREE, false);
```

The `false` argument avoids forced connection initialization. Preserve the
existing `read(value, true)` behavior so the bridge reports `NewData` once for
a new latest value and then reports `OldData` with the retained value.

- [ ] **Step 6: Remove the obsolete object-model option end to end**

Delete this field rather than retaining a no-op compatibility option:

```cpp
std::size_t port_buffer_size{64U};
```

Remove the corresponding range validation from
`ObjectModelImpl::registerComponent` and remove the parameter through the full
call chain:

```text
snapshotComponent
appendServiceContents
appendPortNodes
portMethodSpec
PortBridge::create
```

Remove `buffer_size` from creator captures and make each port-method
fingerprint depend only on the port instance and direction:

```cpp
spec.fingerprint = "port-method|" + pointerFingerprint(&port) + "|" +
                   method_name;
```

Search for the removed API to ensure no stale configuration path survives:

```bash
rg -n 'port_buffer_size|buffer_size.*PortBridge|PortBridge::create' \
  toolchain/tools/rtt_opcua/include toolchain/tools/rtt_opcua/src \
  toolchain/tools/rtt_opcua/tests toolchain/tools/rtt_opcua/README.md
```

Expected: `port_buffer_size` has no matches, and every `PortBridge::create`
call uses the reduced signature.

- [ ] **Step 7: Document the delivery contract and retry boundary**

Add a `Port transport semantics` subsection to the package README. State all
of these points explicitly:

```text
- Remote output-port reads return the latest available sample as NewData.
- A later read without another sample returns OldData and the same value.
- Multiple remote input-port writes may replace one another before RTT reads.
- TaskContextProxy polls ports every 50ms unless configured otherwise.
- A proxy retains a pending input value until the server returns WriteSuccess.
- There are no sample sequence numbers or exactly-once guarantees.
- The bridge is not queued, lossless, OPC UA PubSub, or a deterministic loop.
```

Do not describe attributes, properties, operations, or custom datatype codecs
as changed; their contracts remain independent of this port policy.

- [ ] **Step 8: Review timing tests without inflating sleeps**

Inspect proxy tests for fixed waits:

```bash
rg -n 'sleep_for|sleep_until|wait_for|port_poll_interval' \
  toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp \
  toolchain/tools/rtt_opcua/tests/object_model_test.cpp
```

Tests that need fast transfers must set a `5ms` or `10ms` interval and use an
existing bounded `waitUntil` predicate. Do not compensate for the new default
by increasing fixed sleeps.

- [ ] **Step 9: Run the focused and complete package suites**

```bash
cmake --build toolchain/tools/rtt_opcua/build --parallel \
  --target rtt_opcua_object_model_test rtt_opcua_task_context_proxy_test
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure \
  -R '^(rtt_opcua_object_model_test|rtt_opcua_task_context_proxy_test)$'
cmake --build toolchain/tools/rtt_opcua/build --parallel
ctest --test-dir toolchain/tools/rtt_opcua/build --output-on-failure
```

Expected: both focused tests and the full maintained package suite pass.
Task 9 still repeats the complete graph from a new temporary prefix; this
focused build is only the red/green development loop.

- [ ] **Step 10: Commit latest-value port semantics**

```bash
git -C toolchain/tools/rtt_opcua add \
  include/rtt/opcua/task_context_proxy.hpp \
  include/rtt/opcua/object_model.hpp \
  src/port_bridge.hpp src/port_bridge.cpp src/object_model.cpp \
  tests/object_model_test.cpp tests/task_context_proxy_test.cpp README.md
git -C toolchain/tools/rtt_opcua commit \
  -m "feat: use latest-value OPC UA port semantics"
```

### Task 5: Refactor The OCL Service To Explicit Lifecycle And Publication

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
bool failLocked(const char *operation, std::string error) const;
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

The main lifecycle case must contain this red/green spine:

```cpp
const std::string endpoint_before = deployer.opcUaEndpoint();
BOOST_TEST(!deployer.opcUaReady());
BOOST_REQUIRE(deployer.addPeer(&local));
BOOST_TEST(!deployer.publishComponent(local.getName()));
BOOST_TEST(deployer.opcUaLastError() == "OPC UA server is not running");
BOOST_REQUIRE(deployer.startOpcUa());
BOOST_TEST(deployer.opcUaReady());
BOOST_TEST(deployer.opcUaEndpoint() == endpoint_before);
auto deployer_proxy = RTT::opcua::TaskContextProxy::create(
    endpoint_before, deployer.getName(), {}, &error);
BOOST_REQUIRE_MESSAGE(deployer_proxy != nullptr, error);
auto local_proxy = RTT::opcua::TaskContextProxy::create(
    endpoint_before, local.getName(), {}, &error);
BOOST_TEST(local_proxy == nullptr);
BOOST_REQUIRE(deployer.publishComponent(local.getName()));
local_proxy = RTT::opcua::TaskContextProxy::create(
    endpoint_before, local.getName(), {}, &error);
BOOST_REQUIRE_MESSAGE(local_proxy != nullptr, error);
```

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

The constructor's publication-related work must reduce to service wiring:

```cpp
opcua
    ->addOperation("publishComponent",
                   &OpcUaDeploymentComponent::publishComponent, this,
                   RTT::ClientThread)
    .arg("component", "Local RTT component name.");
opcua
    ->addOperation("unpublishComponent",
                   &OpcUaDeploymentComponent::unpublishComponent, this,
                   RTT::ClientThread)
    .arg("component", "Local RTT component name.");
```

There is no constructor call to either operation and no iteration over
`compmap`.

- [ ] **Step 5: Implement serialized startup as one transaction**

Under `Impl::mutex`, return true unchanged only when the server, model, and
Deployer registration are all ready. Otherwise:

1. call `registerCanonicalTypeProtocols()` (including `ConnPolicy`)
2. call `freezeDataTypeRegistry()` explicitly, before endpoint binding
3. call `server.start()`
4. construct `ObjectModel`
5. strictly register only `*this`, collecting unsupported diagnostics
6. store the Deployer registration and mark ready

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

Define and store the state in `Impl`:

```cpp
enum class LifecycleState {
  created,
  starting,
  running,
  start_failed,
  stopping,
  destroyed,
};

LifecycleState lifecycle{LifecycleState::created};
```

The synchronous transaction must use this failure cleanup on every path after
the listener starts:

```cpp
auto rollbackStart = [this](std::string message) {
  impl_->published.erase(this);
  impl_->model.reset();
  impl_->server.stop();
  impl_->lifecycle = Impl::LifecycleState::start_failed;
  impl_->last_error = std::move(message);
  return false;
};

impl_->lifecycle = Impl::LifecycleState::starting;
const bool canonical_registered =
    RTT::opcua::registerCanonicalTypeProtocols(&error);
const std::string canonical_error = error;
std::string freeze_error;
const auto frozen_order = RTT::opcua::freezeDataTypeRegistry(&freeze_error);
if (!canonical_registered) {
  return rollbackStart(canonical_error);
}
if (!frozen_order) {
  return rollbackStart(freeze_error);
}
if (!impl_->server.start(&error)) {
  return rollbackStart(error);
}
impl_->model = std::make_unique<RTT::opcua::ObjectModel>(
    impl_->server, impl_->options.object_model);
std::vector<RTT::opcua::UnsupportedResource> diagnostics;
auto registration =
    impl_->model->registerComponent(*this, &error, &diagnostics);
if (!registration) {
  impl_->publication_diagnostics[getName()] = std::move(diagnostics);
  return rollbackStart("failed to publish OPC UA Deployer: " + error);
}
impl_->published.emplace(this, std::move(*registration));
impl_->lifecycle = Impl::LifecycleState::running;
impl_->last_error.clear();
return true;
```

Wrap model construction/registration in the existing exception boundary so a
constructor or open62541pp exception becomes `lastError()` and false.

In destruction, set `stopping` under the mutex, swap registrations and remote
peers into local containers, release them outside the mutex, reset the model,
stop the server, then set `destroyed` under the mutex. Releasing registrations
outside the lifecycle mutex allows in-flight callbacks to complete without a
lock cycle while the public state remains non-running.

```cpp
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  impl_->lifecycle = Impl::LifecycleState::stopping;
  remote_peers.swap(impl_->remote_peers);
  published.swap(impl_->published);
}
for (auto &[peer_name, remote] : remote_peers) {
  RTT::TaskContext::removePeer(peer_name);
  remote.proxy->disconnect();
}
remote_peers.clear();
published.clear();
impl_->model.reset();
impl_->server.stop();
{
  std::lock_guard<std::mutex> lock(impl_->mutex);
  impl_->lifecycle = Impl::LifecycleState::destroyed;
}
```

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

`componentUnloaded()` calls `releaseComponent(component)`. That helper moves
erases cached diagnostics and resets the registration while holding
`Impl::mutex`. The potentially blocking reset is part of the serialized unload
transition; keeping the lock prevents a concurrent publish from racing the old
node teardown and component lease drain.

Every successful service command clears `lastError()`. Expected failures set a
specific error and return false without throwing across RTT or OPC UA callback
boundaries. Add endpoint-before/after-start equality and last-error clearing to
the lifecycle test.

Use this lookup/publication ordering:

```cpp
std::lock_guard<std::mutex> lock(impl_->mutex);
RTT::TaskContext *component =
    component_name == getName() || component_name == "this"
        ? this
        : getPeer(component_name);
if (component == nullptr) {
  return failLocked("publishComponent",
                    "unknown local component: " + component_name);
}
if (dynamic_cast<RTT::opcua::TaskContextProxy *>(component) != nullptr) {
  return failLocked("publishComponent",
                    "remote proxy cannot be published: " + component_name);
}
if (impl_->lifecycle != Impl::LifecycleState::running || !impl_->model) {
  return failLocked("publishComponent", "OPC UA server is not running");
}
const auto existing = impl_->published.find(component);
if (existing != impl_->published.end()) {
  impl_->last_error.clear();
  return true;
}
std::vector<RTT::opcua::UnsupportedResource> diagnostics;
auto registration =
    impl_->model->registerComponent(*component, &error, &diagnostics);
if (!registration) {
  impl_->publication_diagnostics[component_name] = std::move(diagnostics);
  return failLocked("publishComponent", error);
}
impl_->published.emplace(component, std::move(*registration));
impl_->publication_diagnostics.erase(component_name);
impl_->last_error.clear();
return true;
```

Before this block, also scan active registrations by `registration.name()` and
reject a matching name owned by a different pointer.

`fail()` acquires `Impl::mutex` and delegates to `failLocked()`; code that
already holds the lifecycle mutex calls `failLocked()` directly. This avoids a
recursive lock while keeping logging and `lastError()` formatting in one
implementation.

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

### Task 6: Freeze On Failed Start And Block Unload While Busy

**Files:**

- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.cpp`
- Modify: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`
- Modify: `toolchain/tools/ocl/deployment/CMakeLists.txt`
- Modify: `toolchain/tools/rtt_opcua/src/datatype_registry.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/type_protocol.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/datatype_registry_test.cpp`

- [ ] **Step 1: Add successful, bind-failed, and validation-failed freeze cases**

Add `successful_start_freezes_registry` and
`failed_start_keeps_registry_frozen` as separate CTest processes. Add a third
`failed_registry_validation_keeps_registry_frozen` process that registers a
provider with a missing dependency before calling start. The bind-failed case
holds a loopback listening socket on the configured port so
`startOpcUa()` reaches registry freeze and then fails endpoint binding.

After each first start attempt, assert `dataTypeRegistryFrozen()` is true and
attempt to register a uniquely named provider. Assert rejection includes the
provider name, states registration is late/frozen, and tells the caller to
restart the process. Release the occupied socket and retry with the same frozen
registry and server configuration; the retry must succeed without reopening
registration.

The core failed-start assertions are:

```cpp
BOOST_TEST(!deployer.startOpcUa());
BOOST_TEST(!deployer.opcUaReady());
BOOST_TEST(RTT::opcua::dataTypeRegistryFrozen());
RTT::opcua::DataTypeProvider late_provider;
late_provider.name = "ocl-failed-start-late-provider";
late_provider.namespace_uri = "urn:orocos:rtt:test:late";
std::string late_error;
BOOST_TEST(!RTT::opcua::registerDataTypeProvider(
    std::move(late_provider), &late_error));
BOOST_TEST(late_error.find("ocl-failed-start-late-provider") !=
           std::string::npos);
BOOST_TEST(late_error.find("late") != std::string::npos);
occupied_port.release();
BOOST_REQUIRE(deployer.startOpcUa());
BOOST_TEST(deployer.opcUaReady());
```

Update both late-registration errors to end with
`the process must be restarted` and assert that text in the existing
`datatype_registry_test` as well as both OCL freeze cases:

```cpp
return fail(error, "late OPC UA datatype provider registration: '" +
                       provider.name +
                       "'; the process must be restarted");
```

Use the same suffix for late type-protocol registration.

Make registry freezing terminal even when dependency ordering fails. Store a
`freeze_error` beside `provider_order`, set `frozen = true` before returning a
validation failure, and return the same stored error from later freeze calls:

```cpp
if (state.frozen) {
  if (!state.freeze_error.empty()) {
    return failOptional(error, state.freeze_error);
  }
  if (error != nullptr) {
    error->clear();
  }
  return state.provider_order;
}
state.frozen = true;
auto order = computeProviderOrder(state, error);
if (!order) {
  state.freeze_error = error == nullptr
                           ? "invalid OPC UA datatype provider graph"
                           : *error;
  return std::nullopt;
}
state.provider_order = *order;
```

Add a private `failOptional()` helper returning
`std::optional<std::vector<std::string>>{}` after assigning its error. Move the
existing-provider equality check in `registerDataTypeProvider()` before the
`state.frozen` rejection so an identical provider remains idempotent on retry;
a new or conflicting provider remains forbidden.

```cpp
std::optional<std::vector<std::string>>
failOptional(std::string *error, const std::string &message) {
  if (error != nullptr) {
    *error = message;
  }
  return std::nullopt;
}
```

Update the existing missing-dependency and cycle tests to expect `frozen ==
true`, a stable repeated freeze error, identical registration success, and
new-provider rejection. This is what makes `StartFailed -> Starting` retryable
without reopening the registry.

The OCL validation-failure case is:

```cpp
RTT::opcua::DataTypeProvider broken;
broken.name = "ocl-broken-provider";
broken.namespace_uri = "urn:orocos:rtt:test:broken";
broken.dependencies = {"ocl-missing-provider"};
BOOST_REQUIRE(RTT::opcua::registerDataTypeProvider(broken, &error));
OCL::OpcUaDeploymentComponent deployer("Deployer", "", deploymentOptions());
BOOST_TEST(!deployer.startOpcUa());
const std::string first_error = deployer.opcUaLastError();
BOOST_TEST(RTT::opcua::dataTypeRegistryFrozen());
BOOST_TEST(RTT::opcua::registerDataTypeProvider(broken, &error));
RTT::opcua::DataTypeProvider missing;
missing.name = "ocl-missing-provider";
missing.namespace_uri = "urn:orocos:rtt:test:missing";
BOOST_TEST(!RTT::opcua::registerDataTypeProvider(
    std::move(missing), &error));
BOOST_TEST(!deployer.startOpcUa());
BOOST_TEST(deployer.opcUaLastError() == first_error);
```

- [ ] **Step 2: Add an unload-after-`BadTimeout` component fixture**

Register a `ComponentLoader` factory for a task with an `RTT::OwnThread`
operation that sets `started`, sleeps for 200 ms, sets `completed`, and returns.
Track its destructor with a third atomic flag. Configure the object-model
operation timeout to 30 ms.

The operation and destructor must expose the race directly:

```cpp
std::int32_t slow(std::uint32_t milliseconds) {
  slow_started.store(true);
  std::this_thread::sleep_for(std::chrono::milliseconds(milliseconds));
  slow_completed.store(true);
  return 42;
}

~SlowTask() override { slow_destroyed.store(true); }
```

Load and explicitly publish the component, call the operation with a low-level
open62541 client, and assert the response is `BadTimeout` while
`pendingOperationCount` behavior remains covered in `rtt_opcua`.

- [ ] **Step 3: Prove unload blocks on the retained lease**

Call `deployer.unloadComponent(name)` through `std::async`. Before the slow
operation finishes, assert the future is not ready and the destructor flag is
false. Then assert the operation completes, unload returns true, the component
is destroyed, and its OPC UA root is absent. Immediately load and publish a
new instance with the same name to prove the old registration was fully reset.

Use a bounded future assertion rather than a timing-only sleep:

```cpp
auto unload = std::async(std::launch::async, [&deployer] {
  return deployer.unloadComponent("SlowComponent");
});
BOOST_TEST(unload.wait_for(std::chrono::milliseconds(40)) ==
           std::future_status::timeout);
BOOST_TEST(!slow_destroyed.load());
BOOST_REQUIRE(unload.wait_for(std::chrono::seconds(2)) ==
              std::future_status::ready);
BOOST_TEST(unload.get());
BOOST_TEST(slow_completed.load());
BOOST_TEST(slow_destroyed.load());
```

- [ ] **Step 4: Run the new cases under ASan/UBSan/LSan**

```bash
ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
  -R '^ocl_opcua_deployment_(successful_start_freezes_registry|failed_start_keeps_registry_frozen|failed_registry_validation_keeps_registry_frozen|unload_waits_for_timed_out_operation)$'
```

Repeat these cases in the temporary sanitizer build created by the installed
verification task. Expected: no use-after-free, leak, deadlock, or teardown
crash.

- [ ] **Step 5: Confirm the existing lifetime implementation is sufficient**

The existing `ComponentRegistration::reset()` and retained pending invocation
lease are the implementation under test; no additional lifetime production
change is planned. If the new regression is red, stop this task and invoke
`superpowers:systematic-debugging` to identify the violated lease boundary,
then amend this plan with the evidence before editing production lifetime
code. Do not add sleeps or extend the request timeout to hide the race.

- [ ] **Step 6: Commit package changes by ownership**

```bash
git -C toolchain/tools/ocl add \
  deployment/OpcUaDeploymentComponent.cpp \
  deployment/tests/opcua_deployment_test.cpp deployment/CMakeLists.txt
git -C toolchain/tools/ocl commit \
  -m "test: cover OPC UA freeze and unload lifetime"
```

Commit the frozen-registry diagnostics separately:

```bash
git -C toolchain/tools/rtt_opcua add \
  src/datatype_registry.cpp src/type_protocol.cpp \
  tests/datatype_registry_test.cpp
git -C toolchain/tools/rtt_opcua commit \
  -m "fix: explain frozen OPC UA registration lifetime"
```

### Task 7: Stop `deployer-opcua` From Starting Automatically

**Files:**

- Modify: `toolchain/tools/ocl/bin/deployer.cpp`
- Modify: `tools/test-opcua-custom-datatypes.sh`

- [ ] **Step 1: Add an installed executable regression check first**

In `tools/test-opcua-custom-datatypes.sh`, launch the installed target-specific
`deployer-opcua` on a fresh loopback port with no startup script. Give it an
isolated `HOME` and the already constructed temporary runtime paths. Assert the
process remains alive but a TCP connection to the configured port fails. Send
`SIGTERM`, wait for clean shutdown, and print its log on failure.

Add this check after OCL installation and before fixture startup:

```bash
DEPLOYER="$PREFIX/bin/deployer-opcua-$TARGET"
STOPPED_LOG="$TEST_ROOT/deployer-stopped.log"
STOPPED_PORT="$(ruby -rsocket -e \
  'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]')"
"$DEPLOYER" --opcua-port "$STOPPED_PORT" >"$STOPPED_LOG" 2>&1 &
STOPPED_PID="$!"
sleep 0.2
kill -0 "$STOPPED_PID"
if ruby -rsocket -e \
  'TCPSocket.new("127.0.0.1", Integer(ARGV.fetch(0))).close' \
  "$STOPPED_PORT" 2>/dev/null; then
  orocos_rock_die "deployer-opcua started before opcua.start()"
fi
kill -TERM "$STOPPED_PID"
wait "$STOPPED_PID"
```

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

After script processing, the next executable statement must be:

```cpp
rc = (result ? 0 : -1);
```

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

### Task 8: Exercise Import, Load, Start, And Publish From The Installed Prefix

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

The shared class keeps the existing publication loop and accepts the factory
name:

```cpp
class FixtureComponent final : public RTT::TaskContext {
public:
  explicit FixtureComponent(
      const std::string &name = "fixture/component")
      : RTT::TaskContext(name, RTT::TaskContext::PreOperational),
        float64_array_("Float64Array", {1.25, 2.5}),
        int32_array_("Int32Array", {10, 20}),
        string_array_("StringArray", {"alpha", "beta"}),
        rt_string_("RtString", RTT::rt_string("initial")),
        point_("Point", Point{1.0, 2.0}),
        envelope_("Envelope", Envelope{{3.0, 4.0}, 5}),
        point_array_("PointArray", {{6.0, 7.0}, {8.0, 9.0}}) {
    publish(float64_array_);
    publish(int32_array_);
    publish(string_array_);
    publish(rt_string_);
    publish(point_);
    publish(envelope_);
    publish(point_array_);
  }

private:
  template <typename T> void publish(Surface<T> &surface);
  Surface<std::vector<double>> float64_array_;
  Surface<std::vector<std::int32_t>> int32_array_;
  Surface<std::vector<std::string>> string_array_;
  Surface<RTT::rt_string> rt_string_;
  Surface<Point> point_;
  Surface<Envelope> envelope_;
  Surface<PointArray> point_array_;
};
```

Define the `publish` template body in the header using the same property,
attribute, port, and OwnThread operation registrations already present in
`fixture_component.cpp`.

```cpp
template <typename T>
void FixtureComponent::publish(Surface<T> &surface) {
  addProperty(surface.stem + "Property", surface.property);
  addAttribute(surface.stem + "Attribute", surface.attribute);
  addPort(surface.output);
  addPort(surface.input);
  addOperation(surface.stem + "Echo", &Surface<T>::echo, &surface,
               RTT::OwnThread)
      .arg("value", "Value to return.");
  addOperation(surface.stem + "Emit", &Surface<T>::emit, &surface,
               RTT::OwnThread)
      .arg("value", "Value to publish.");
  addOperation(surface.stem + "Take", &Surface<T>::take, &surface,
               RTT::OwnThread);
}
```

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

```cmake
orocos_component(fixture-components fixture_component_plugin.cpp)
target_compile_features(fixture-components PRIVATE cxx_std_20)
target_include_directories(
  fixture-components PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}
)
```

Add `fixture-components` to the existing target `foreach`; the Orocos package
macro owns its component-library install destination.

The unsupported type/component are exact:

```cpp
struct UnsupportedValue {
  std::int32_t value{0};
};

class UnsupportedComponent final : public RTT::TaskContext {
public:
  explicit UnsupportedComponent(const std::string &name)
      : RTT::TaskContext(name) {
    addProperty("UnsupportedValue", value_);
  }

private:
  UnsupportedValue value_{7};
};
```

Register `UnsupportedValue` through
`TemplateTypeInfo<UnsupportedValue, false>` in `FixtureTypekit::loadTypes()`;
leave `FixtureTransport::registerTransport()` unchanged for that type so it
returns false and no OPC UA codec exists. The component plugin contains:

```cpp
ORO_CREATE_COMPONENT_LIBRARY()
ORO_LIST_COMPONENT_TYPE(orocos::opcua::fixture::FixtureComponent)
ORO_LIST_COMPONENT_TYPE(orocos::opcua::fixture::UnsupportedComponent)
```

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

Configure and install both scripts from the fixture CMake project:

```cmake
configure_file(deployer-no-start.ops.in deployer-no-start.ops @ONLY)
configure_file(deployer-start.ops.in deployer-start.ops @ONLY)
install(
  FILES
    ${CMAKE_CURRENT_BINARY_DIR}/deployer-no-start.ops
    ${CMAKE_CURRENT_BINARY_DIR}/deployer-start.ops
  DESTINATION share/orocos_opcua_fixture
)
```

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

Use typed RTT callers for the remote service checks:

```cpp
auto deployer = RTT::opcua::TaskContextProxy::create(
    endpoint, deployer_name, options, &error);
require(deployer != nullptr, error);
RTT::OperationCaller<bool(const std::string &, const std::string &,
                          RTT::ConnPolicy)>
    connect = deployer->getOperation("connect");
RTT::OperationCaller<bool(const std::string &, RTT::ConnPolicy)> stream =
    deployer->getOperation("stream");
RTT::OperationCaller<bool(const std::string &, const std::string &,
                          RTT::ConnPolicy)>
    create_stream = deployer->getOperation("createStream");
require(connect.ready(), "Deployer connect operation is missing");
require(stream.ready(), "Deployer stream operation is missing");
require(create_stream.ready(), "Deployer createStream operation is missing");
RTT::Service::shared_ptr opcua_service = deployer->provides("opcua");
require(opcua_service != nullptr, "Deployer opcua service is missing");
RTT::OperationCaller<bool(const std::string &)> publish =
    opcua_service->getOperation("publishComponent");
RTT::OperationCaller<std::vector<std::string>(const std::string &)>
    unsupported = opcua_service->getOperation("unsupportedResources");
require(publish.ready(), "publishComponent operation is missing");
require(!publish("unsupported"),
        "unsupported component publication unexpectedly succeeded");
require(!unsupported("unsupported").empty(),
        "unsupported publication diagnostics are missing");
```

- [ ] **Step 5: Run both deployer modes in the root verifier**

First launch with `deployer-no-start.ops` and prove the port stays closed.
Then launch a fresh process with `deployer-start.ops`, wait for the loopback
endpoint, and run `fixture-client --deployer Deployer --component sample`.
Capture separate logs and always terminate/wait through the existing trap.

The positive launch and client call use the installed artifacts only:

```bash
START_SCRIPT="$PREFIX/share/orocos_opcua_fixture/deployer-start.ops"
DEPLOYER_LOG="$TEST_ROOT/deployer-start.log"
"$DEPLOYER" --opcua-port "$PORT" --start "$START_SCRIPT" \
  >"$DEPLOYER_LOG" 2>&1 &
SERVER_PID="$!"
ready=0
for _ in $(seq 1 200); do
  if ruby -rsocket -e \
    'TCPSocket.new("127.0.0.1", Integer(ARGV.fetch(0))).close' \
    "$PORT" 2>/dev/null; then
    ready=1
    break
  fi
  kill -0 "$SERVER_PID" 2>/dev/null || break
  sleep 0.05
done
if [ "$ready" -ne 1 ]; then
  sed -n '1,240p' "$DEPLOYER_LOG" >&2
  orocos_rock_die "explicit OPC UA deployer did not become ready"
fi
"$CLIENT" --typekit "$TYPEKIT" --transport "$TRANSPORT" \
  --endpoint "opc.tcp://127.0.0.1:$PORT/rtt" \
  --deployer Deployer --component sample
```

Keep the original standalone `fixture-server` pass as a lower-level transport
test; the deployer pass is additional coverage, not a replacement.

At the end of a successful run, write
`$TEST_ROOT/runtime-env.sh` with shell-quoted values for the temporary `HOME`,
`OROCOS_TARGET`, `PATH`, `LD_LIBRARY_PATH`, `RTT_COMPONENT_PATH`,
`CMAKE_PREFIX_PATH`, and `PKG_CONFIG_PATH` already used by the verifier. This
file is evidence and a convenience for manual acceptance; it must refer only
to the selected install/dependency prefixes below `/tmp`.

Generate it with Bash's shell-quoting formatter:

```bash
RTT_COMPONENT_PATH="$PREFIX/lib/orocos/$TARGET:$PREFIX/lib/orocos/$TARGET/orocos_opcua_fixture"
export RTT_COMPONENT_PATH
{
  printf 'export HOME=%q\n' "$TEST_HOME"
  printf 'export OROCOS_TARGET=%q\n' "$TARGET"
  printf 'export PATH=%q\n' "$PREFIX/bin:$PATH"
  printf 'export LD_LIBRARY_PATH=%q\n' "$LD_LIBRARY_PATH"
  printf 'export RTT_COMPONENT_PATH=%q\n' "$RTT_COMPONENT_PATH"
  printf 'export CMAKE_PREFIX_PATH=%q\n' "$INSTALLED_PREFIX_PATH"
  printf 'export PKG_CONFIG_PATH=%q\n' "$PKG_CONFIG_PATH"
} >"$TEST_ROOT/runtime-env.sh"
```

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

### Task 9: Run Final Sanitizer And Manual TaskBrowser Acceptance

**Files:**

- Modify: `docs/src/opcua-deployer-lifecycle-design.md`
- Modify: `docs/src/user-guide.md`
- Modify: `docs/src/package-test-results.md`
- Modify: `tools/check-package-tests-ci.rb`
- Modify: `tools/test-package.sh`

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

The user-guide command sequence must be:

```text
deployer-opcua
  import("sample_typekit")
  loadComponent("sample", "SampleComponent")
  opcua.start()
  opcua.publishComponent("sample")

ctaskbrowser-opcua opc.tcp://127.0.0.1:4840/rtt Deployer
ctaskbrowser-opcua --import sample_typekit \
  opc.tcp://127.0.0.1:4840/rtt sample
```

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
  tools/check-package-tests-ci.rb tools/test-package.sh
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
