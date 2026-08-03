# Orocos OPC UA Custom Datatype And Sequence Type Design

Date: 2026-08-03

Status: Accepted design basis for follow-on work. This is an architecture
specification, not an implementation plan.

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

## Goals

- Keep `rtt_opcua` independent of MetaNC and all other applications.
- Let downstream typekits add native OPC UA support through runtime plugins.
- Support the canonical RTT sequence type names.
- Use namespace URIs and stable string NodeIds rather than fixed namespace
  indexes.
- Load all datatype definitions before the OPC UA server starts.
- Make unsupported resources visible and diagnosable.
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
8. `deployer-opcua` starts its OPC UA server only after startup deployment
   scripts have run and type plugins have registered.
9. RTT-based clients load application type plugins explicitly before creating a
   proxy. Remote servers cannot trigger automatic local library loading.
10. Components publish every resource whose RTT type has an OPC UA protocol.
    Unsupported resources are omitted but must produce warnings and remain
    queryable through diagnostics.
11. Automatic oroGen/typegen generation is a later improvement. The first
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
- Defer `deployer-opcua` server startup until startup scripts complete.
- Queue components selected for publication until the server is ready.
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
  -> load site configuration
  -> execute startup .ops scripts
  -> import RTT typekits and their OPC UA transport plugins
  -> validate the datatype-provider registry
  -> register provider namespace URIs
  -> materialize custom datatypes with resolved namespace indexes
  -> configure and start the open62541 server
  -> create datatype and encoding nodes
  -> publish the deployer and queued components
  -> reconcile later component interface changes
```

If no startup scripts exist, the server starts immediately after the empty
startup phase.

Components loaded after startup may be published when all their required
providers were already registered. Loading a new datatype provider after server
startup returns an explicit error. Automatic server restart and live datatype
mutation are deferred.

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

## Publication And Unsupported-Type Warnings

Publication creates every operation, property, attribute, and port supported by
the loaded protocol registry. A missing protocol does not silently erase a
resource.

For each unsupported resource, log a warning containing:

- component name
- full service/resource path
- resource kind
- canonical RTT type name
- reason, such as missing protocol or missing provider

Example:

```text
[Warning] OPC UA: component 'rt_api' skipped operation
'resources.axes_groups.command' because RTT type
'/meta_nc/rt_api/CommandWire' has no registered OPC UA protocol.
```

Warning behavior:

- Emit one warning per unsupported resource when it first appears.
- Do not repeat warnings during every reconciliation interval.
- Recompute diagnostics when the component interface revision changes.
- Log when a previously unsupported resource becomes supported.
- Store the same entries for a deployment operation conceptually named
  `opcua.unsupportedResources(component)`.
- Structural address-space or server failures still make publication fail.
- MetaNC migration tests require no unsupported resources for its intended
  public interface.

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
- Verify unsupported warnings are emitted once, queryable, and updated when the
  interface changes.
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

## Remaining Details For The Implementation Plan

- Final public C++ names and ownership model for logical providers, bound
  registries, and codecs.
- Exact MetaNC namespace URI spelling.
- Stable string NodeId escaping and collision rules for custom datatype names.
- Representation of OPC UA DataTypeDefinition and binary encoding references in
  the address space.
- How provider dependencies are declared and sorted.
- Exact deployment operation names for starting the server and querying
  unsupported resources.
- Exact CLI parsing and repeatability rules for `ctaskbrowser-opcua --import`.
- Client diagnostics when only some required application plugins are installed.
- Whether oroGen/typegen should later generate the registration translation
  unit, datatype metadata, or both.
