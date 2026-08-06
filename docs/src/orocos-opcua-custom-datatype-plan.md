# Orocos OPC UA Custom Datatype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement generic migration steps 1 through 8 from the accepted OPC
UA custom datatype design without adding or changing MetaNC code.

**Architecture:** RTT owns four canonical sequence type names. `rtt_opcua`
keeps logical provider metadata process-wide, freezes it before the first
endpoint starts, and creates a separate codec and datatype binding for every
server or client namespace table. OCL imports application packages before
binding, starts the server after deployment scripts complete, and exposes
deterministic publication diagnostics.

**Tech Stack:** C++20, Orocos RTT/OCL, open62541 1.4.15, open62541pp 0.21.2,
CMake, Boost.Test, mdBook, AddressSanitizer, UndefinedBehaviorSanitizer, and
LeakSanitizer.

**Execution status (2026-08-04):** Generic migration steps 1 through 8 and the
application-neutral installed-prefix verification gate are complete on
`gnulinux`. Plan Task 9 is the verification gate for those generic steps; it
is not MetaNC migration step 9. MetaNC migration steps 9 through 13 remain out
of scope and are recorded in
`/tmp/metanc-opcua-custom-datatype-migration-handoff.md`.

> [!NOTE]
> The queued-publication and automatic-start behavior recorded in Task 6 is a
> description of the completed first implementation, not the current lifecycle
> contract. It is superseded by
> [OPC UA Deployer Lifecycle Design](./opcua-deployer-lifecycle-design.md).
> A replacement implementation plan will be written after that specification
> is reviewed.

## Global Constraints

- Implement only generic migration steps 1 through 8. Do not modify MetaNC.
- Work only in the linked RTT, `rtt_opcua`, OCL, and root worktrees on the
  local `codex/orocos-opcua-custom-datatypes` branches.
- Never install into or source an environment from `~/.orocos`; use a newly
  created directory below `/tmp` and remove inherited Orocos environment
  variables before every authoritative build or test.
- Require C++20 and compile maintained changed sources with `-Wall -Wextra
  -Wpedantic -Werror`.
- Keep CORBA sources present and configure CORBA off.
- Remove `array`, `ints`, `strings`, and `rt_string` without aliases. Register
  only `Float64Array`, `Int32Array`, `StringArray`, and `RtString`.
- Use provider-owned namespace URIs and provider-supplied string NodeIds
  verbatim. Reject empty strings, embedded NUL bytes, and collisions; never
  derive or escape custom datatype NodeIds from RTT names.
- Register providers and RTT protocols before the first endpoint binding.
  Identical registrations are idempotent; conflicting, missing-dependency,
  cyclic, and late registrations fail with deterministic messages.
- A remote endpoint may never request or trigger local library loading.
- Publish the full supported RTT interface. Do not add allowlists, publication
  modes, PKI, RBAC, or non-loopback listening.

---

### Task 1: Canonical RTT And OCL Sequence Names

**Files:**

- Modify: `toolchain/tools/rtt/rtt/typekit/RealTimeTypekitStdTypes.cpp`
- Modify: `toolchain/tools/rtt/rtt/typekit/RTStringTypeInfo.hpp`
- Modify: `toolchain/tools/rtt/rtt/typekit/RealTimeTypekitConstructors.cpp`
- Modify: `toolchain/tools/rtt/tests/typekit_test.cpp`
- Modify: `toolchain/tools/rtt/tests/property_composition_test.cpp`
- Modify: `toolchain/tools/rtt/tests/types_test.cpp`
- Modify: `toolchain/tools/rtt/tests/rtstring_test.cpp`
- Modify: `toolchain/tools/rtt/tests/state_test.cpp`
- Modify: `toolchain/tools/rtt/tests/testtypes/types/array_types.cpp`
- Modify: `toolchain/tools/rtt/tests/type_discovery_container_test.cpp`
- Modify: `toolchain/tools/rtt/tests/type_discovery_struct_test.cpp`
- Modify: `toolchain/tools/rtt/tests/testPropMarshVectLegacy.cpf`
- Modify: `toolchain/tools/rtt/doc/xml/orocos-rtt-scripting.xml`
- Modify: `toolchain/tools/rtt/doc/xml/orocos-rtt-plugins.xml`
- Modify: `toolchain/tools/rtt/doc/xml/orocos-task-context.xml`
- Modify: `toolchain/tools/ocl/ocl/ocltoolkit.cpp`
- Modify: `toolchain/tools/ocl/deployment/tests/ComponentA.cpf`
- Modify: `toolchain/tools/ocl/deployment/tests/ComponentB.cpf`
- Modify: `toolchain/tools/ocl/taskbrowser/TaskBrowser.cpp`

**Interfaces:**

- Consumes: the existing RTT `SequenceTypeInfo<T>` and `RTStringTypeInfo`.
- Produces: RTT repository entries for `std::vector<double>` as
  `Float64Array`, `std::vector<std::int32_t>` as `Int32Array`,
  `std::vector<std::string>` as `StringArray`, and `RTT::rt_string` as
  `RtString`.

- [ ] **Step 1: Extend the canonical type repository test first**

Add the four canonical names to `canonical_names`, add the four removed names
to `legacy_names`, and add these exact C++ mapping assertions:

```cpp
RTT_CHECK_CANONICAL_TYPE(std::vector<double>, "Float64Array");
RTT_CHECK_CANONICAL_TYPE(std::vector<std::int32_t>, "Int32Array");
RTT_CHECK_CANONICAL_TYPE(std::vector<std::string>, "StringArray");
#ifdef OS_RT_MALLOC
RTT_CHECK_CANONICAL_TYPE(RTT::rt_string, "RtString");
#endif
```

- [ ] **Step 2: Run the focused RTT test and observe the expected failure**

Run from the RTT worktree with a clean environment:

```bash
env -u OROCOS_PREFIX -u LD_LIBRARY_PATH -u RTT_COMPONENT_PATH \
    -u CMAKE_PREFIX_PATH -u PKG_CONFIG_PATH -u RUBYLIB \
    cmake --build build --parallel --target typekit_test
env -u OROCOS_PREFIX -u LD_LIBRARY_PATH -u RTT_COMPONENT_PATH \
    -u CMAKE_PREFIX_PATH -u PKG_CONFIG_PATH -u RUBYLIB \
    ctest --test-dir build --output-on-failure -R '^typekit_test$'
```

Expected: `testCanonicalBuiltinTypesAreRegistered` reports missing canonical
sequence names and still-registered legacy names.

- [ ] **Step 3: Register only the canonical sequence names**

Make `loadStdTypes` contain these registrations:

```cpp
ti->addType(new StdStringTypeInfo("String"));
ti->addType(new SequenceTypeInfo<std::vector<double>>("Float64Array"));
ti->addType(
    new SequenceTypeInfo<std::vector<std::int32_t>>("Int32Array"));
ti->addType(
    new SequenceTypeInfo<std::vector<std::string>>("StringArray"));
```

Change `RTStringTypeInfo` and its constructor lookups from `rt_string` to
`RtString`. Remove OCL's `strings` and `ints` registrations because RTT now
owns those C++ types.

- [ ] **Step 4: Migrate bundled runtime examples and fixtures**

Replace script-visible `array` constructors and declarations with
`Float64Array`, replace script-visible `rt_string` with `RtString`, change CPF
type values for `std::vector<double>` to `Float64Array`, and update tests that
attempt to re-register `std::vector<int>` to use the existing `Int32Array`
`TypeInfo`. Keep ordinary English uses of the words “array”, “strings”, and
“ints” unchanged.

- [ ] **Step 5: Run the complete RTT and OCL focused tests**

```bash
env -u OROCOS_PREFIX -u LD_LIBRARY_PATH -u RTT_COMPONENT_PATH \
    -u CMAKE_PREFIX_PATH -u PKG_CONFIG_PATH -u RUBYLIB \
    cmake --build build --parallel
env -u OROCOS_PREFIX -u LD_LIBRARY_PATH -u RTT_COMPONENT_PATH \
    -u CMAKE_PREFIX_PATH -u PKG_CONFIG_PATH -u RUBYLIB \
    ctest --test-dir build --output-on-failure
```

Expected: all configured RTT tests pass and repository searches show no
runtime registration or script-visible use of the four removed names.

- [ ] **Step 6: Commit the package changes separately**

```bash
git -C toolchain/tools/rtt add rtt tests doc
git -C toolchain/tools/rtt commit -m "feat: canonicalize RTT sequence type names"
git -C toolchain/tools/ocl add ocl deployment taskbrowser
git -C toolchain/tools/ocl commit -m "refactor: consume canonical RTT sequence types"
```

### Task 2: Logical Datatype Provider Registry

**Files:**

- Create: `toolchain/tools/rtt_opcua/include/rtt/opcua/datatype_registry.hpp`
- Create: `toolchain/tools/rtt_opcua/src/datatype_registry.cpp`
- Create: `toolchain/tools/rtt_opcua/tests/datatype_registry_test.cpp`
- Modify: `toolchain/tools/rtt_opcua/CMakeLists.txt`

**Interfaces:**

- Consumes: `opcua::DataType`, `opcua::NodeId`, and process-local provider
  registration from explicitly loaded plugins.
- Produces:

```cpp
struct LogicalDataTypeId {
  std::string namespace_uri;
  std::string type_node_id;
  std::string binary_encoding_node_id;
  auto operator<=>(const LogicalDataTypeId &) const = default;
};

enum class CustomDataTypeKind { structure, enumeration, union_type };

class DataTypeFactoryContext {
public:
  std::uint16_t namespaceIndex(std::string_view namespace_uri) const;
  ::opcua::NodeId nodeId(const LogicalDataTypeId &id) const;
  const UA_DataType *dataType(const LogicalDataTypeId &id) const noexcept;
};

using DataTypeFactory =
    std::function<::opcua::DataType(const DataTypeFactoryContext &)>;

struct CustomDataTypeDefinition {
  std::string name;
  LogicalDataTypeId id;
  CustomDataTypeKind kind{CustomDataTypeKind::structure};
  std::string schema_fingerprint;
  DataTypeFactory materialize;
};

struct DataTypeProvider {
  std::string name;
  std::string namespace_uri;
  std::vector<std::string> dependencies;
  std::vector<CustomDataTypeDefinition> data_types;
};

bool registerDataTypeProvider(DataTypeProvider provider,
                              std::string *error = nullptr);
bool dataTypeRegistryFrozen() noexcept;
std::optional<std::vector<std::string>>
freezeDataTypeRegistry(std::string *error = nullptr);
```

- [ ] **Step 1: Write one lifecycle test covering all registration rules**

The test registers two providers in reverse dependency order, confirms an
identical registration succeeds, confirms changed fingerprints and colliding
type/encoding NodeIds fail, then freezes through endpoint binding and confirms
a third provider is rejected as late. Separate test processes invoke the test
binary with `--run_test=missing_dependency` and `--run_test=dependency_cycle`
so each failure starts with a fresh process-wide registry.

- [ ] **Step 2: Run the new target and observe the missing API failure**

```bash
cmake -S . -B build -DBUILD_TESTING=ON -DRTT_OPCUA_WARNINGS_AS_ERRORS=ON
cmake --build build --parallel --target rtt_opcua_datatype_registry_test
```

Expected: compilation fails because `datatype_registry.hpp` does not exist.

- [ ] **Step 3: Implement deterministic validation and freezing**

Use a mutex-protected process singleton. Validate nonempty names, URIs,
fingerprints, factories, and string NodeIds; reject embedded `\0`; require each
definition URI to equal its provider URI; reject type/encoding equality and
cross-provider collisions. Sort dependencies and providers lexicographically
when multiple topological orders are possible. Return messages beginning with
one of these stable prefixes:

```text
invalid OPC UA datatype provider
conflicting OPC UA datatype provider
missing OPC UA datatype provider dependency
cyclic OPC UA datatype provider dependency
late OPC UA datatype provider registration
```

- [ ] **Step 4: Run registry tests individually and together**

```bash
ctest --test-dir build --output-on-failure \
  -R '^rtt_opcua_datatype_registry_test'
```

Expected: all registry lifecycle subprocess cases pass under `-Werror`.

- [ ] **Step 5: Commit**

```bash
git add CMakeLists.txt include/rtt/opcua/datatype_registry.hpp \
  src/datatype_registry.cpp tests/datatype_registry_test.cpp
git commit -m "feat: add logical OPC UA datatype registry"
```

### Task 3: Endpoint-Bound Protocols And Codecs

**Files:**

- Modify: `toolchain/tools/rtt_opcua/include/rtt/opcua/type_protocol.hpp`
- Create: `toolchain/tools/rtt_opcua/include/rtt/opcua/endpoint_type_registry.hpp`
- Create: `toolchain/tools/rtt_opcua/src/endpoint_type_registry.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/type_protocol.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/type_protocol_test.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/datatype_registry_test.cpp`
- Modify: `toolchain/tools/rtt_opcua/CMakeLists.txt`

**Interfaces:**

- Consumes: frozen logical providers and RTT `TypeInfo` transport entries.
- Produces:

```cpp
using DataTypeReference =
    std::variant<::opcua::NodeId, LogicalDataTypeId>;
using VariantReader = std::function<bool(::opcua::Variant *)>;
using VariantWriter = std::function<bool(const ::opcua::Variant &)>;

class TypeCodec {
public:
  virtual ~TypeCodec() = default;
  virtual bool toVariant(const RTT::base::DataSourceBase::shared_ptr &,
                         ::opcua::Variant *) const = 0;
  virtual bool assignVariant(
      const ::opcua::Variant &,
      const RTT::base::DataSourceBase::shared_ptr &) const = 0;
  virtual RTT::base::DataSourceBase::shared_ptr
  makeDataSource(const ::opcua::Variant &) const = 0;
  virtual RTT::base::DataSourceBase::shared_ptr
  makeProxyDataSource(VariantReader, VariantWriter = {}) const = 0;
  virtual bool portValue(const RTT::base::OutputPortInterface *,
                         ::opcua::Variant *) const = 0;
  const ::opcua::NodeId &dataTypeNodeId() const noexcept;
  ::opcua::ValueRank valueRank() const noexcept;
  bool hasValue() const noexcept;

protected:
  TypeCodec(::opcua::NodeId data_type, ::opcua::ValueRank value_rank,
            bool has_value);
};

class TypeProtocol : public RTT::types::TypeTransporter {
public:
  using VariantReader = RTT::opcua::VariantReader;
  using VariantWriter = RTT::opcua::VariantWriter;
  virtual DataTypeReference dataType() const = 0;
  virtual std::string registrationFingerprint() const = 0;
  virtual std::unique_ptr<TypeCodec>
  bind(const ::opcua::NodeId &, const UA_DataType &,
       std::string *error = nullptr) const = 0;
};

class EndpointTypeRegistry {
public:
  static std::shared_ptr<EndpointTypeRegistry>
  create(const std::vector<std::pair<std::string, std::uint16_t>> &namespaces,
         std::string *error = nullptr);
  const TypeCodec *codecForTypeInfo(const RTT::types::TypeInfo *) const;
  const TypeCodec *codecForTypeName(std::string_view) const;
  const TypeCodec *codecForDataSource(
      const RTT::base::DataSourceBase::shared_ptr &) const;
  ::opcua::Span<const ::opcua::DataType> customDataTypes() const noexcept;
  const ::opcua::DataType *
  dataType(const LogicalDataTypeId &id) const noexcept;
  std::optional<std::uint16_t>
  namespaceIndex(std::string_view namespace_uri) const noexcept;
};
```

- [ ] **Step 1: Replace global-codec assertions with endpoint assertions**

In `type_protocol_test.cpp`, create a binding containing the standard namespace
table and assert all canonical RTT types resolve through
`binding->codecForTypeName`. In `datatype_registry_test.cpp`, bind the same
provider twice with namespace indexes 3 and 9 and assert the resulting custom
type and binary-encoding NodeIds use 3 and 9 respectively.

- [ ] **Step 2: Run tests and observe missing binding failures**

```bash
cmake --build build --parallel --target \
  rtt_opcua_type_protocol_test rtt_opcua_datatype_registry_test
```

Expected: compilation fails on `EndpointTypeRegistry` and `TypeCodec`.

- [ ] **Step 3: Split logical protocol factories from bound codecs**

Move the current scalar and void conversion behavior into `TypeCodec`
implementations. `TypeProtocol` instances retain only a datatype reference and
a stable registration fingerprint plus a `bind` factory. Make
`registerTypeProtocol` accept an existing protocol only when its datatype
reference and fingerprint match, reject non-idempotent replacement, and reject
all registration after the provider registry freezes. Remove lazy protocol
registration after freeze; call `registerCanonicalTypeProtocols()` before each
endpoint is bound.

- [ ] **Step 4: Materialize providers and bind every installed RTT protocol**

Reserve the complete custom datatype vector before invoking factories so
member pointers remain stable. Materialize in provider dependency order and
definition declaration order. Verify every returned `opcua::DataType` has the
declared type and binary-encoding NodeIds. Resolve built-ins only in namespace
zero with `opcua::findDataType`; resolve custom references only from the
materialized logical map.

- [ ] **Step 5: Run focused tests**

```bash
ctest --test-dir build --output-on-failure \
  -R '^rtt_opcua_(datatype_registry|type_protocol)_test$'
```

Expected: canonical codecs bind, custom namespace indexes vary safely, and
unknown/missing protocol references produce deterministic errors.

- [ ] **Step 6: Commit**

```bash
git add CMakeLists.txt include/rtt/opcua src tests
git commit -m "refactor: bind OPC UA codecs per endpoint"
```

### Task 4: Canonical Array And RtString Codecs

**Files:**

- Modify: `toolchain/tools/rtt_opcua/src/type_descriptor.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/type_protocol.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/type_protocol_test.cpp`

**Interfaces:**

- Consumes: Task 1 canonical RTT names and Task 3 endpoint codec binding.
- Produces: one-dimensional built-in OPC UA array codecs for `Float64Array`,
  `Int32Array`, and `StringArray`, plus a scalar OPC UA String codec for
  `RtString`.

- [ ] **Step 1: Add round-trip tests for all four codecs**

For each type, test `toVariant`, `assignVariant`, `makeDataSource`, writable and
read-only proxy datasources, and output-port last-value conversion. Assert the
three vectors report `ValueRank::OneDimension` with element datatypes Double,
Int32, and String; assert `RtString` reports scalar String.

- [ ] **Step 2: Run and observe unsupported codec failures**

```bash
cmake --build build --parallel --target rtt_opcua_type_protocol_test
ctest --test-dir build --output-on-failure \
  -R '^rtt_opcua_type_protocol_test$'
```

Expected: the four canonical sequence codec lookups return null.

- [ ] **Step 3: Implement array and RtString codecs**

Use `Variant(std::vector<T>)` and `Variant::to<std::vector<T>>()` for the three
built-in arrays. Convert `RTT::rt_string` to and from `std::string` at the codec
boundary. Reject scalar/array rank mismatches and wrong element datatypes
without throwing across callbacks.

- [ ] **Step 4: Run and commit**

```bash
ctest --test-dir build --output-on-failure \
  -R '^rtt_opcua_(type_protocol|foundation)_test$'
git add src/type_descriptor.cpp src/type_protocol.cpp tests/type_protocol_test.cpp
git commit -m "feat: transport canonical RTT sequence types over OPC UA"
```

### Task 5: Server And Client Custom Datatype Installation

**Files:**

- Modify: `toolchain/tools/rtt_opcua/include/rtt/opcua/server.hpp`
- Modify: `toolchain/tools/rtt_opcua/include/rtt/opcua/server_options.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/server.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/client_session.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/client_session.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/operation_dispatcher.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/operation_dispatcher.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/port_bridge.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/port_bridge.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/remote_operation.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/remote_port.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/task_context_proxy.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/server_test.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/task_context_proxy_test.cpp`

**Interfaces:**

- Consumes: `EndpointTypeRegistry`.
- Produces:

```cpp
std::shared_ptr<const EndpointTypeRegistry> Server::typeRegistry() const;
std::optional<std::uint16_t>
Server::namespaceIndex(std::string_view namespace_uri) const noexcept;
```

`ServerOptions::additional_namespace_uris` is a `std::vector<std::string>`
registered before provider URIs to make namespace-order tests explicit.

- [ ] **Step 1: Add server ownership and namespace-order tests**

Use a `BOOST_GLOBAL_FIXTURE` to register the fixture provider and protocol
before any test in each executable can start a server. Register an unrelated
namespace before the fixture provider, start the server,
and assert the provider index is neither assumed nor equal to the binding from
a server without the unrelated namespace. Assert the server exposes a non-null
type registry for its whole running lifetime.

- [ ] **Step 2: Add a proxy test that requires a client custom datatype**

The test registers a fixture POD structure and protocol before server startup,
publishes it as an operation, property, attribute, input port, and output port,
then creates `TaskContextProxy` and round-trips every resource. Without client
configuration installation, synchronization or the first decode must fail.

- [ ] **Step 3: Run the tests and record the expected failures**

```bash
cmake --build build --parallel --target \
  rtt_opcua_server_test rtt_opcua_object_model_test \
  rtt_opcua_task_context_proxy_test
ctest --test-dir build --output-on-failure \
  -R '^rtt_opcua_(server|object_model|task_context_proxy)_test$'
```

Expected: custom variants cannot be created/decoded because endpoint configs
do not contain the provider datatypes.

- [ ] **Step 4: Bind and install server datatypes before startup**

Construct the open62541pp server, register RTT, additional, and sorted provider
namespace URIs, build the endpoint registry from `namespaceArray`, call
`config().addCustomDataTypes(binding->customDataTypes())`, and only then call
`runIterate`. Store the binding before `native_server` in `Server::Impl` so the
native server is destroyed first.

- [ ] **Step 5: Perform two-phase client connection**

Use a discovery client with built-in types to connect, read the namespace
array, and disconnect. Bind local providers to that array, add custom datatypes
to a new final `ClientConfig`, construct the final client, and connect again.
Store the binding before the client so the client is destroyed first. A remote
provider name never causes a local import.

- [ ] **Step 6: Thread bound codecs through object-model and proxy paths**

Replace every global `protocolForTypeInfo`, `protocolForTypeName`, and
`protocolForDataSource` conversion lookup with the owning server/client
`EndpointTypeRegistry`. Capture shared binding ownership in callbacks and port
bridges so no codec or `UA_DataType` pointer outlives its registry.

- [ ] **Step 7: Run and commit**

```bash
ctest --test-dir build --output-on-failure -R '^rtt_opcua_.*_test$'
git add include/rtt/opcua src tests
git commit -m "feat: install custom datatypes in OPC UA endpoints"
```

### Task 6: Provider Datatype And Binary-Encoding Nodes

**Files:**

- Modify: `toolchain/tools/rtt_opcua/include/rtt/opcua/endpoint_type_registry.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/endpoint_type_registry.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/server.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/server_test.cpp`

**Interfaces:**

- Consumes: materialized `opcua::DataType` objects.
- Produces:

```cpp
bool EndpointTypeRegistry::publishDataTypeNodes(::opcua::Server &server,
                                                std::string *error) const;
```

- [ ] **Step 1: Add URI/string-NodeId browse tests**

Connect a plain client, resolve the provider URI in its namespace array, and
assert these nodes exist with the exact provider-supplied identifiers:

```text
nsu=<provider-uri>;s=<type-node-id>
nsu=<provider-uri>;s=<binary-encoding-node-id>
```

Assert the type node class is DataType, the encoding node class is Object, the
type has a forward `HasEncoding` reference, and reading
`DataTypeDefinition` returns a StructureDefinition whose default encoding is
the declared string NodeId.

- [ ] **Step 2: Run and observe unknown-node failures**

```bash
cmake --build build --parallel --target rtt_opcua_server_test
ctest --test-dir build --output-on-failure -R '^rtt_opcua_server_test$'
```

Expected: reads fail with `BadNodeIdUnknown`.

- [ ] **Step 3: Publish nodes before server startup**

For structure and union types, add the DataType below `Structure` or `Union`;
for enumerations, add it below `Enumeration`. Add an Object named
`Default Binary` below the custom DataType with type
`DataTypeEncodingType` and reference `HasEncoding`. Treat any NodeId collision
as startup failure. open62541 derives `DataTypeDefinition` from the installed
`UA_DataType` and the matching DataType node.

- [ ] **Step 4: Run and commit**

```bash
ctest --test-dir build --output-on-failure -R '^rtt_opcua_server_test$'
git add include/rtt/opcua/endpoint_type_registry.hpp \
  src/endpoint_type_registry.cpp src/server.cpp tests/server_test.cpp
git commit -m "feat: publish OPC UA custom datatype nodes"
```

### Task 7: OCL Deferred Startup And Explicit Client Imports

**Files:**

- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.hpp`
- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.cpp`
- Modify: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`
- Modify: `toolchain/tools/ocl/bin/deployer.cpp`
- Modify: `toolchain/tools/ocl/bin/ctaskbrowser-opcua.cpp`
- Modify: `toolchain/tools/ocl/bin/CMakeLists.txt`

**Interfaces:**

- Consumes: provider registration performed by imported local packages.
- Produces:

```cpp
bool OpcUaDeploymentComponent::startOpcUa();
```

and a repeatable client option:

```text
ctaskbrowser-opcua [--import PACKAGE]...
                  <opc.tcp://host:port/path> <ComponentName>
```

- [ ] **Step 1: Change deployment tests to assert stopped construction**

Construct the deployer and assert `!opcUaReady()`. Load or queue a local
component, call `startOpcUa()`, assert it becomes ready, and prove the deployer,
site-file components, and pre-start peers are published. Call `startOpcUa()` a
second time and require success without duplicate nodes.

- [ ] **Step 2: Run and observe the constructor-start failure**

```bash
cmake --build build --parallel --target ocl_opcua_deployment_test
ctest --test-dir build --output-on-failure \
  -R '^ocl_opcua_deployment_test$'
```

Expected: `opcUaReady()` is already true immediately after construction.

- [ ] **Step 3: Queue publication until explicit startup**

Construct `RTT::opcua::Server` stopped and keep `ObjectModel` null. Store
selected component pointers in an ordered pending map. `startOpcUa()` starts
the server, constructs the model, publishes the deployer and pending components,
and is idempotent. Add service operation `opcua.start`. Unloading a component
removes both pending and active registrations.

- [ ] **Step 4: Start only after successful startup scripts**

In `deployer.cpp`, execute site and command-line startup files first. When they
all succeed, call `dc.startOpcUa()` and log the endpoint. If imports, scripts,
provider validation, or server startup fail, return failure and do not expose a
partially configured endpoint. With an empty startup-file list, call startup
immediately after the empty loop.

- [ ] **Step 5: Add CLI parser behavior tests**

Add CTest invocations proving `--help` documents `--import`, missing package
arguments fail, repeated `--import fixture_a --import=fixture_b` is accepted by
the parser, and exactly two positional arguments are required. These tests stop
before opening the interactive browser.

- [ ] **Step 6: Import packages before proxy construction**

Parse `--import PACKAGE` and `--import=PACKAGE` in left-to-right order, reject
empty packages and unknown options, and call:

```cpp
if (!RTT::ComponentLoader::Instance()->import(package, "")) {
  std::cerr << "Unable to import local Orocos package '" << package << "'.\n";
  return -1;
}
```

Only after all imports succeed may `TaskContextProxy::create` freeze and bind
the local registry.

- [ ] **Step 7: Run and commit**

```bash
ctest --test-dir build --output-on-failure \
  -R '^(ocl_opcua_deployment_test|ctaskbrowser_opcua_)'
git add deployment bin
git commit -m "feat: bind OPC UA after deployment imports"
```

### Task 8: Unsupported Resource Diagnostics And Warning Deduplication

**Files:**

- Modify: `toolchain/tools/rtt_opcua/include/rtt/opcua/object_model.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/operation_dispatcher.hpp`
- Modify: `toolchain/tools/rtt_opcua/src/operation_dispatcher.cpp`
- Modify: `toolchain/tools/rtt_opcua/src/object_model.cpp`
- Modify: `toolchain/tools/rtt_opcua/tests/object_model_test.cpp`
- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.hpp`
- Modify: `toolchain/tools/ocl/deployment/OpcUaDeploymentComponent.cpp`
- Modify: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`

**Interfaces:**

- Consumes: full interface snapshots and endpoint-bound codec lookup.
- Produces:

```cpp
struct UnsupportedResource {
  std::string component;
  std::string path;
  std::string kind;
  std::string type_name;
  std::string reason;
  std::string message() const;
  auto operator<=>(const UnsupportedResource &) const = default;
};

std::vector<UnsupportedResource>
ObjectModel::unsupportedResources(std::string_view component) const;

std::vector<std::string>
OpcUaDeploymentComponent::unsupportedResources(const std::string &component)
    const;
```

The OCL `opcua.unsupportedResources(component)` operation returns the formatted
string vector, encoded through `StringArray`, so diagnostics do not create a
bootstrap custom datatype.

- [ ] **Step 1: Add diagnostics and warning-callback tests**

Add an unregistered fixture type as an operation input/return, property,
attribute, input port, and output port. Inject an
`ObjectModelOptions::warning_sink` callback, register the component, reconcile
twice, and assert each sorted diagnostic appears once in the sink and once in
`unsupportedResources`. Remove the unsupported resources, reconcile, and
assert diagnostics clear and one recovery message is emitted for each resource.

- [ ] **Step 2: Run and observe silent omission/current port failure**

```bash
cmake --build build --parallel --target rtt_opcua_object_model_test
ctest --test-dir build --output-on-failure \
  -R '^rtt_opcua_object_model_test$'
```

Expected: operations/properties/attributes are silently omitted, unsupported
ports can fail reconciliation, and no query API exists.

- [ ] **Step 3: Snapshot supported nodes and unsupported resources together**

Return a `ComponentSnapshot` containing the `NodeMap` and a sorted diagnostic
vector. Omit the complete unsupported resource, including port metadata
folders. Extend `OperationSchema` with the first unsupported type and reason so
operation diagnostics identify the concrete argument or result type.

- [ ] **Step 4: Diff diagnostics during reconciliation**

Store current diagnostics per component. Emit the exact warning from
`UnsupportedResource::message()` only for additions, emit an Info recovery
message only for removals, and do not re-emit unchanged entries on periodic
reconciliation. Default `warning_sink` writes through `RTT::Logger`; tests may
inject a callback.

- [ ] **Step 5: Expose OCL diagnostics and test them through a proxy**

Add the service operation, call it both locally and through the deployer proxy,
and assert deterministic `StringArray` results. Unknown components return an
empty vector and set `lastError` to `no such published OPC UA component: NAME`.

- [ ] **Step 6: Run and commit**

```bash
ctest --test-dir build --output-on-failure -R '^rtt_opcua_.*_test$'
git add include/rtt/opcua/object_model.hpp src tests
git commit -m "feat: report unsupported OPC UA resources"
git -C toolchain/tools/ocl add deployment
git -C toolchain/tools/ocl commit -m "feat: expose OPC UA publication diagnostics"
```

### Task 9: Installed External Fixture And Final Verification

**Files:**

- Create: `tests/opcua-custom-datatypes/CMakeLists.txt`
- Create: `tests/opcua-custom-datatypes/package.xml`
- Create: `tests/opcua-custom-datatypes/fixture_types.hpp`
- Create: `tests/opcua-custom-datatypes/fixture_typekit.cpp`
- Create: `tests/opcua-custom-datatypes/fixture_transport.cpp`
- Create: `tests/opcua-custom-datatypes/fixture_component.cpp`
- Create: `tests/opcua-custom-datatypes/fixture_client.cpp`
- Create: `tools/test-opcua-custom-datatypes.sh`
- Modify: `tools/test-package.sh`
- Modify: `docs/src/package-test-results.md`
- Modify: `docs/src/SUMMARY.md`
- Modify: `docs/src/orocos-opcua-custom-datatype-design.md`

**Interfaces:**

- Consumes: installed RTT, `rtt_opcua`, and OCL packages only.
- Produces: application-neutral proof for a POD structure, nested POD
  structure, and `std::vector<POD>` registered by an external typekit and OPC
  UA transport plugin after `rtt_opcua` is installed.

- [ ] **Step 1: Write the external fixture before adding its runner**

Define `Point`, `Envelope{Point point; std::int32_t quality;}`, and
`PointArray`. The provider URI is `urn:orocos:rtt:fixture`; logical IDs are
`types/Point`, `encodings/Point/Binary`, `types/Envelope`, and
`encodings/Envelope/Binary`. Register RTT names
`/orocos/fixture/Point`, `/orocos/fixture/Envelope`, and
`/orocos/fixture/PointArray`. The server publishes operations, writable
property and attribute, and both port directions for all representative types.

- [ ] **Step 2: Configure against an empty temporary prefix and observe failure**

```bash
OPCUA_TEST_ROOT="$(mktemp -d /tmp/orocos-opcua-custom-datatypes.XXXXXX)"
cmake -S tests/opcua-custom-datatypes \
  -B "$OPCUA_TEST_ROOT/fixture-build" \
  -DCMAKE_PREFIX_PATH="$OPCUA_TEST_ROOT/prefix"
```

Expected: configuration fails because RTT and `rtt_opcua` are not installed.

- [ ] **Step 3: Implement the isolated runner**

The script requires `--prefix`, rejects any prefix below the current user's
home Orocos directory, clears inherited Orocos/CMake/pkg-config/Ruby variables,
builds and installs RTT, `rtt_opcua`, and OCL into that prefix, then configures
the fixture solely from the installed environment. It starts the fixture
server as a child process, waits for a readiness file below the temporary root,
runs the client, and always terminates the child through a shell trap.

- [ ] **Step 4: Verify cross-process custom types and canonical sequences**

The client explicitly imports the fixture package, then round-trips
`Float64Array`, `Int32Array`, `StringArray`, `RtString`, `Point`, `Envelope`, and
`PointArray` through operations, properties, attributes, and ports. It verifies
URI/string datatype nodes, a non-1 provider namespace index, and an empty
unsupported-resource report.

- [ ] **Step 5: Run release and sanitizer matrices**

```bash
OPCUA_TEST_ROOT="$(mktemp -d /tmp/orocos-opcua-custom-datatypes.XXXXXX)"
OPCUA_DEPENDENCY_PREFIX=/tmp/orocos-opcua-dependencies/prefix
env -u OROCOS_PREFIX -u LD_LIBRARY_PATH -u RTT_COMPONENT_PATH \
    -u CMAKE_PREFIX_PATH -u PKG_CONFIG_PATH -u RUBYLIB \
    ./tools/test-opcua-custom-datatypes.sh \
      --prefix "$OPCUA_TEST_ROOT/release-prefix" \
      --dependency-prefix "$OPCUA_DEPENDENCY_PREFIX"
env -u OROCOS_PREFIX -u LD_LIBRARY_PATH -u RTT_COMPONENT_PATH \
    -u CMAKE_PREFIX_PATH -u PKG_CONFIG_PATH -u RUBYLIB \
    CXXFLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer' \
    LDFLAGS='-fsanitize=address,undefined' \
    ASAN_OPTIONS='detect_leaks=1:halt_on_error=1' \
    UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1' \
    ./tools/test-opcua-custom-datatypes.sh \
      --prefix "$OPCUA_TEST_ROOT/sanitizer-prefix" \
      --dependency-prefix "$OPCUA_DEPENDENCY_PREFIX"
```

Expected: all package tests, cross-process fixture tests, leak checks, and
warning scans pass; `ldd` and build logs contain the selected `/tmp` prefix and
no `~/.orocos` path.

- [ ] **Step 6: Run documentation and repository policy checks**

```bash
rg -n '"(array|ints|strings|rt_string)"' \
  toolchain/tools/rtt toolchain/tools/ocl toolchain/tools/rtt_opcua
mdbook build docs
git diff --check
```

Expected: no removed runtime names, mdBook succeeds, and no whitespace errors.

- [ ] **Step 7: Record evidence and commit root changes**

Update `package-test-results.md` with exact commands, counts, durations, temp
prefixes, compiler versions, sanitizer settings, and any explicitly remaining
platform gap. Mark generic steps 1 through 8 implemented in the design without
changing the MetaNC 9 through 13 boundary.

```bash
git add docs tests tools
git commit -m "test: verify external OPC UA custom datatypes"
```

### Task 10: Coordinated Review And Integration Gate

**Files:**

- Review only: all files changed by Tasks 1 through 9
- Verify: `/tmp/metanc-opcua-custom-datatype-migration-handoff.md`

**Interfaces:**

- Consumes: clean, committed RTT, `rtt_opcua`, OCL, and root worktrees.
- Produces: review evidence suitable for deciding whether to fast-forward each
  repository's default branch. This task does not push remote feature branches.

- [ ] **Step 1: Review every package diff against its default branch**

```bash
git -C toolchain/tools/rtt diff --stat liufang/dev...HEAD
git -C toolchain/tools/rtt_opcua diff --stat liufang/dev...HEAD
git -C toolchain/tools/ocl diff --stat liufang/dev...HEAD
git diff --stat liufang/main...HEAD
```

Check ownership lifetimes, exception containment, callback captures, registry
locking, namespace handling, duplicate/late registration, proxy reconnection,
diagnostic stability, and shutdown under pending operations.

- [ ] **Step 2: Repeat the authoritative verification after the final commit**

Run the exact release, sanitizer, cross-process, warning, policy, and mdBook
commands from Task 9 from a new `/tmp` root. Do not reuse build trees that
predate the final commit.

- [ ] **Step 3: Confirm repository and handoff boundaries**

```bash
git status --short --branch
git -C toolchain/tools/rtt status --short --branch
git -C toolchain/tools/rtt_opcua status --short --branch
git -C toolchain/tools/ocl status --short --branch
test -s /tmp/metanc-opcua-custom-datatype-migration-handoff.md
```

Expected: only intentional committed changes exist; no MetaNC repository path
appears in any changed source; the handoff contains steps 9 through 13 and the
temporary-prefix/Xenomai completion gate.

- [ ] **Step 4: Present integration evidence before changing defaults**

Report commits, tests, sanitizer results, remaining platform gaps, and the
handoff path. Fast-forward local/default branches and push only after the user
accepts the review evidence and the repository remote/default-branch policy is
reconfirmed.

---

{{#include opcua-taskbrowser-custom-datatype-evaluation-plan.md}}
