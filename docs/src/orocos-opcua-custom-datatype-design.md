# Orocos OPC UA Custom Datatype And Sequence Type Design

Date: 2026-08-03
Updated: 2026-08-05

Status: The generic implementation now follows the explicit-start and static,
strict-publication lifecycle specified in
[OPC UA Deployer Lifecycle Design](./opcua-deployer-lifecycle-design.md).
Final Task 8 verification remains pending. MetaNC migration steps 9 through 13
remain a separate delivery.

## Purpose

Define how the generic `rtt_opcua` package supports sequence types and
application-defined RTT types that are compiled after `rtt_opcua`, including
the MetaNC wire types. This support must allow the old MetaNC OPC UA packages to
be removed after their consumers migrate.

## Delivery Boundaries

This design is implemented as two separately reviewed deliveries:

1. The generic toolchain delivery covers migration steps 1 through 8 in RTT,
   `rtt_opcua`, OCL, and `orocos-rock`. It proves the extension API with an
   application-neutral external fixture and must not depend on MetaNC code.
2. The MetaNC migration covers steps 9 through 13 after the generic delivery
   has landed. It adds the application-owned provider plugin, migrates
   consumers, validates Xenomai deployment, and removes the old MetaNC OPC UA
   packages only after no consumer remains.

> [!IMPORTANT]
> The current `orocos-rock` session implements only generic migration steps 1
> through 8. MetaNC migration steps 9 through 13 are explicitly out of scope
> here and get their own repository session, plan, and verification gate.

The generic delivery is implemented by coordinated changes in RTT,
`rtt_opcua`, OCL, and this repository. Its installed-prefix fixture is
application-neutral: it defines its own typekit and OPC UA transport plugin,
then builds them only after the generic packages have been installed. See
[OPC UA Custom Datatype Verification](./opcua-custom-datatype-verification.md)
for the reproducible test contract and current platform evidence.

## Goals

- Keep `rtt_opcua` independent of MetaNC and all other applications.
- Let downstream typekits add native OPC UA support through runtime plugins.
- Support the canonical RTT sequence type names.
- Use namespace URIs and stable string NodeIds rather than fixed namespace
  indexes.
- Load all datatype definitions before the OPC UA server starts.
- Reject partial component publication and make unsupported resources visible
  and diagnosable.
- Support the same custom types in server and RTT proxy client processes.

## Non-Goals

- Rebuild `rtt_opcua` for each application.
- Add MetaNC type names or headers to `rtt_opcua`.
- Preserve the old MetaNC `ns=1` NodeIds or address-space layout.
- Preserve `meta_nc_opcua_service`, `opcua_bind`, or its explicit `expose*`
  operations.
- Preserve the old sequence type names as aliases.
- Automatically load executable code requested by a remote OPC UA server.
- Generate arbitrary OPC UA mappings from C++ reflection in the first
  migration.
- Encode application values as JSON or opaque `ByteString` payloads merely to
  avoid defining native OPC UA datatypes.
- Add publication allowlists, security modes, PKI, or access control as part of
  this work.

## Confirmed Decisions

1. Remove `array`, `ints`, `strings`, and `rt_string` without compatibility
   aliases.
2. Replace them with `Float64Array`, `Int32Array`, `StringArray`, and
   `RtString`.
3. `rtt_opcua` exports a generic extension API. Application packages build
   plugins against that API after `rtt_opcua` is installed.
4. MetaNC continues to own its wire structures and OPC UA datatype metadata.
5. Each application datatype provider owns a namespace URI and uses stable
   string NodeIds.
6. Namespace indexes are resolved separately for each server and client
   endpoint. No provider may assume namespace index `1`.
7. Custom datatype providers must load before the OPC UA server starts. Late
   registration is rejected initially.
8. `deployer-opcua` never starts its OPC UA server automatically. Startup
   scripts or the embedded TaskBrowser import type plugins, then call
   `opcua.start()` explicitly.
9. RTT-based clients load application type plugins explicitly before creating a
   proxy. Remote servers cannot trigger automatic local library loading.
10. `opcua.start()` freezes the datatype registry for the process lifetime and
    publishes only the complete Deployer interface.
11. Every other local component requires an explicit
    `opcua.publishComponent(name)` call. `Server=true` never triggers OPC UA
    publication.
12. Component publication is strict and transactional. An unsupported resource
    rejects the whole component with no partial address-space model, and the
    diagnostics remain queryable.
13. Automatic oroGen/typegen generation is a later improvement. The first
    MetaNC migration uses a small application-owned registration plugin around
    its existing metadata.

## Dependency Direction

```text
rtt_opcua
  -> RTT
  -> open62541pp

rt_api_types-opcua plugin
  -> rtt_opcua
  -> rt_api_types RTT typekit
  -> MetaNC rt-api-contract
```

`rtt_opcua` never links MetaNC, includes MetaNC headers, or contains a registry
entry naming a MetaNC type.

## Package Responsibilities

### `rtt_opcua`

- Define the public datatype-provider and protocol-factory interfaces.
- Own the process-wide pre-start registration registry.
- Validate provider names, namespace URIs, logical type identifiers, encoding
  identifiers, and registration conflicts.
- Resolve namespace URIs to endpoint-local numeric namespace indexes.
- Materialize endpoint-bound `opcua::DataType` definitions.
- Install custom datatype definitions into server and client configurations.
- Create OPC UA DataType and binary-encoding nodes in the server address space.
- Provide reusable codecs for scalars, one-dimensional arrays, structures, and
  `RtString`.
- Publish supported RTT resources and report unsupported ones.
- Keep server and proxy conversion code independent of application types.

### RTT and OCL

- Register the canonical sequence names.
- Remove the lowercase legacy sequence names and update constructors,
  operators, tests, examples, and documentation.
- Keep `deployer-opcua` server startup under the explicit `opcua.start()` API.
- Reject component publication before startup instead of queueing it.
- Publish only the Deployer during startup and require explicit publication for
  every other local component.
- Add the generic `RTT::ConnPolicy` structure codec needed to publish the full
  Deployer interface.
- Add explicit application package imports to `ctaskbrowser-opcua`.
- Expose publication diagnostics through the OPC UA deployment service.

### MetaNC `rt-api-contract`

- Continue owning wire structures and their field-level OPC UA metadata.
- Replace fixed numeric namespace indexes with factories that accept a resolved
  namespace context.
- Own the MetaNC namespace URI and stable logical datatype identifiers.
- Keep datatype definitions independent of the generic RTT object model.

### MetaNC `rt_api_types`

- Own the RTT typekit for MetaNC wire types.
- Build and install the application OPC UA transport plugin.
- Register a codec factory for each transported RTT `TypeInfo`.
- Register the MetaNC datatype provider exactly once when the package is
  imported.
- Reuse datatype builders from `rt-api-contract`; do not duplicate structure
  layouts in the transport plugin.

## Runtime Extension Model

The public API names below are conceptual. Exact C++ names belong in the
implementation plan.

```cpp
struct LogicalDataTypeId {
    std::string namespace_uri;
    std::string type_node_id;
    std::string binary_encoding_node_id;
};

struct DataTypeProvider {
    std::string provider_name;
    std::string namespace_uri;
    DataTypeFactory materialize;
};

struct TypeProtocolFactory {
    std::string rtt_type_name;
    LogicalDataTypeId data_type;
    CodecFactory bind;
};
```

Registration stores logical descriptions and factories, not endpoint-specific
numeric namespace indexes. A server or client creates a bound registry for its
own namespace table. Bound codecs perform RTT datasource and port conversion
using the materialized `opcua::DataType` objects for that endpoint.

This requires evolving the current global
`TypeProtocol::dataTypeNodeId()` contract. A process-global protocol cannot
safely store a numeric namespace index because two endpoints can assign
different indexes to the same namespace URI.

## Example: `MachineTopologyWire`

The generic package is built first. MetaNC later builds a shared transport
plugin conceptually named:

```text
rt_api_types-opcua.so
```

The plugin registers:

```text
RTT type:
  /meta_nc/rt_api/MachineTopologyWire

C++ type:
  meta_nc::rt_api::MachineTopologyWire

Provider namespace:
  urn:metanc:rt-api

Logical type NodeId:
  types/MachineTopologyWire

Logical binary encoding NodeId:
  encodings/MachineTopologyWire/Binary

Metadata factory:
  makeMachineTopologyWireDataTypes(resolved_namespace_context)
```

The current MetaNC metadata already describes the C++ fields with
`opcua::DataTypeBuilder`. It must stop constructing static definitions with
hardcoded values such as `NodeId(1, 5101)` and instead materialize definitions
using the endpoint's resolved namespace index.

## Namespace And NodeId Rules

The generic RTT object model remains in:

```text
nsu=urn:orocos:rtt;s=rtt/components/...
```

Application datatype definitions use their provider-owned namespace. A MetaNC
example is:

```text
nsu=urn:metanc:rt-api;s=types/MachineTopologyWire
nsu=urn:metanc:rt-api;s=encodings/MachineTopologyWire/Binary
```

Rules:

- Namespace URIs are stable public identifiers.
- Numeric namespace indexes are runtime details.
- Type and encoding NodeIds are stable strings.
- Provider registration rejects duplicate logical identifiers with different
  definitions.
- Full canonical RTT names identify codec registrations.
- A provider owns every custom type referenced by its definitions, or declares
  an explicit dependency on another provider.

## Canonical Sequence Types

| RTT name | C++ representation | OPC UA representation |
| --- | --- | --- |
| `Float64Array` | `std::vector<double>` | `Double`, one dimension |
| `Int32Array` | `std::vector<std::int32_t>` | `Int32`, one dimension |
| `StringArray` | `std::vector<std::string>` | `String`, one dimension |
| `RtString` | `RTT::rt_string` | `String`, scalar |

The first three use OPC UA built-in element datatypes and therefore do not need
custom OPC UA DataType nodes. An array of an application structure uses the
application structure datatype with one-dimensional value rank.

The legacy names are removed rather than retained as aliases. Downstream `.ops`
scripts, CPF files, tests, documentation, and type-name comparisons migrate in
the same rollout.

## Server Startup Flow

```text
construct deployer with OPC UA server stopped
  -> load site configuration and execute requested startup scripts
  -> import RTT typekits and their OPC UA transport plugins
  -> call opcua.start() locally
  -> register generic protocols, including RTT::ConnPolicy
  -> freeze and validate the datatype-provider registry for process lifetime
  -> resolve provider namespace URIs and materialize endpoint-bound datatypes
  -> configure and start the open62541 server
  -> create datatype and encoding nodes
  -> strictly publish the complete Deployer interface only
  -> call opcua.publishComponent(name) for each other local component
```

If no startup scripts exist, the server remains stopped until a local caller
invokes `opcua.start()`. `ctaskbrowser-opcua` cannot connect before that call;
the embedded TaskBrowser can.

Components loaded after startup may be published when all their required
providers were already registered. Loading a new datatype provider after server
startup returns an explicit error. The first start attempt freezes the registry
even if endpoint startup later fails. Automatic server restart and live
datatype mutation are deferred.

## RTT Client Flow

An RTT-based client must load the matching local typekit and OPC UA plugin before
constructing `TaskContextProxy`.

```bash
ctaskbrowser-opcua \
  --import rt_api_types \
  opc.tcp://127.0.0.1:4840/rtt \
  rt_api
```

The client then:

```text
imports the requested local packages
  -> freezes its local datatype-provider registry
  -> connects using built-in OPC UA types
  -> resolves server namespace URIs
  -> materializes endpoint-bound custom datatypes
  -> installs them in the client configuration
  -> discovers and constructs the RTT proxy interface
```

The remote server may advertise required provider names for diagnostics, but it
must never cause an RTT client to load a local shared library automatically.

MetaNC's non-RTT SDK links its contract metadata normally and installs the same
custom datatypes into its own OPC UA client configuration. It does not load an
Orocos transport plugin.

## Strict Publication And Unsupported-Type Diagnostics

> [!IMPORTANT]
> The lifecycle design linked above supersedes the original dynamic
> reconciliation and revision-replacement parts of this section. Publication
> now validates and commits one static snapshot. There is no periodic graph
> reconciliation, component replacement, or public unpublish operation in this
> version.

Publication validates a complete component snapshot before committing its
address-space nodes. Every operation, property, attribute, constant, and port
must use a type bound in the endpoint protocol registry. A missing protocol
rejects the complete candidate revision; it never silently erases one resource
from an otherwise published component.

For each unsupported resource, log a warning containing:

- component name
- full service/resource path
- resource kind
- canonical RTT type name
- reason, such as missing protocol or missing provider

Example:

```text
[Warning] OPC UA: component 'rt_api' rejected operation
'resources.axes_groups.command' because RTT type
'/meta_nc/rt_api/CommandWire' has no registered OPC UA protocol.
```

Diagnostic behavior:

- Return false from `opcua.publishComponent(component)`.
- Roll back every node created for the candidate component.
- Leave the object-model revision unchanged.
- Emit a concrete warning for each unsupported resource found by the explicit
  publication attempt. No background process repeats diagnostics.
- Store the same entries for
  `opcua.unsupportedResources(component)`, including after failed publication.
- Treat repeated publication of the same component instance as an idempotent
  success. Runtime replacement and republishing are deferred.
- Require an empty unsupported-resource report when the Deployer or another
  component is initially published successfully.

## Registration And Error Rules

- Empty provider names, namespace URIs, RTT names, or logical NodeIds are
  rejected.
- Conflicting provider, RTT type, datatype NodeId, or encoding NodeId
  registrations fail before server startup.
- Identical idempotent registrations succeed.
- Missing provider dependencies fail server startup with a concrete diagnostic.
- Late provider registration fails and identifies the provider and server
  state.
- Missing local client codecs prevent affected proxy resources from being
  constructed and produce explicit client diagnostics.
- Conversion failures map to OPC UA status codes and do not let C++ exceptions
  cross callback boundaries.
- Registry and bound datatype objects remain alive until every server, client,
  node, variant, and proxy using them has been destroyed.

## Approaches Rejected

### Rebuild `rtt_opcua` With MetaNC

This reverses the dependency boundary, prevents reuse by other applications,
and makes the toolchain depend on downstream code.

### Put MetaNC Types Directly In `rtt_opcua`

This gives the generic transport ownership of application contracts and repeats
the architecture problem of the old central MetaNC package.

### Fixed Numeric Namespace Indexes

Indexes depend on endpoint registration order and are not portable between
servers or clients.

### Remote Automatic Plugin Loading

Allowing a network peer to select a local shared library is an unacceptable
code-loading boundary.

### Opaque JSON Or ByteString Encoding

This loses native OPC UA datatype identity, method signatures, validation, and
interoperability.

### Full Generator Work In The First Migration

Automatic generation for nested structures, fixed arrays, enums, custom
conversions, and stable binary schemas is valuable but larger than the runtime
extension requirement. The runtime API must be proven first.

## Migration Order

1. Canonicalize RTT/OCL sequence names and update their tests.
2. Add the logical provider registry and endpoint-bound codecs to `rtt_opcua`.
3. Add generic array and `RtString` protocols.
4. Install custom datatype definitions in both server and client
   configurations.
5. Add provider namespace and DataType node publication.
6. Defer `deployer-opcua` startup until startup scripts complete.
7. Add explicit `--import` handling to `ctaskbrowser-opcua`.
8. Add unsupported-resource diagnostics and deduplicated warnings.
9. Refactor MetaNC datatype builders to accept a namespace context.
10. Add the MetaNC OPC UA transport plugin to the `rt_api_types` package.
11. Migrate MetaNC `.ops`, CPF, SDK, tests, documentation, and NodeId usage.
12. Run cross-process server, proxy, SDK, and Xenomai validation.
13. Remove `meta_nc_opcua_service`, `meta_nc_opcua_type_protocol`, the old
    binder, and the obsolete demo package only after no consumer remains.

## Verification Requirements

### Generic Package

- Build an external fixture typekit and OPC UA plugin after `rtt_opcua` is
  already built and installed.
- Round-trip `Float64Array`, `Int32Array`, `StringArray`, and `RtString` through
  operations, properties, attributes, and ports.
- Round-trip a custom structure, a nested structure, and an array of custom
  structures through server and `TaskContextProxy`.
- Vary namespace registration order and prove that no test assumes index `1`.
- Verify custom DataType and binary-encoding nodes by namespace URI and string
  NodeId.
- Verify provider conflicts and missing dependencies fail deterministically.
- Verify late registration is rejected.
- Verify an unsupported type rejects the complete component, leaves no nodes or
  revision change, and remains queryable through diagnostics.
- Verify `start()` publishes only the complete Deployer and that
  `Server=true` components require explicit publication.
- Verify `RTT::ConnPolicy` round-trips through the proxy and exposes every
  Deployer connection operation.
- Verify endpoint teardown waits for timed-out asynchronous calls to release
  their component leases, and that the Deployer rejects unload of a published
  component while no unpublish operation exists.
- Verify no old sequence type names appear in the runtime type repository.
- Run cross-process and sanitizer tests from a temporary install prefix.

### MetaNC Migration

- Import `rt_api_types` and confirm its OPC UA transport plugin registers every
  intended wire type.
- Publish the intended `rt_api` interface with an empty unsupported-resource
  report.
- Test every SDK-used operation, property, attribute, and port datatype.
- Test native MetaNC SDK calls and RTT `TaskContextProxy` calls.
- Update all old `array`, `ints`, `strings`, and `rt_string` references.
- Confirm no build or runtime dependency on `meta_nc_opcua_*` remains.
- Validate the installed toolchain and MetaNC deployment in the target Xenomai
  environment.

## Deferred MetaNC And Future Details

- Exact MetaNC namespace URI spelling.
- Whether oroGen/typegen should later generate the registration translation
  unit, datatype metadata, or both.
- MetaNC's exact provider split if its wire datatypes span more than one
  independently versioned contract package.
- PKI, non-loopback endpoints, session authentication, and access control.
