# Read-Only C-Array Indexing Design

Date: 2026-08-09

## Status

Approved in discussion. This document defines the RTT behavior needed to read
an indexed element from a read-only fixed C-array snapshot while preserving
assignment through writable parents.

## Context

RTT can expose a fixed C-array member of a read-only structure through
`ReadOnlyPartDataSource<types::carray<T> >`. This datasource deliberately
isolates its presentation buffer so callers cannot mutate the original value.

`CArrayTypeInfo::getMember()` currently creates indexed elements only after it
narrows the array datasource to `AssignableDataSource`. That makes valid reads
such as the following fail with a semantic error:

```text
rt_api.motion_bank.spindles.process_data_out.last().spindles[0]
```

The `last()` operation returns a snapshot. Its array and indexed elements are
read-only, but they must remain inspectable.

## Behavioral Contract

Indexability and assignability are separate capabilities:

| Parent | Element read | Element assignment |
|---|---:|---:|
| Writable C-array datasource | Yes | Yes |
| Read-only C-array datasource | Yes | No |
| Operation-return snapshot | Yes | No |

The existing writable behavior remains unchanged. In particular, assigning an
element through a writable property, attribute, variable, or structure member
must still update its parent and propagate `updated()` notifications.

Reading through an operation-return snapshot must not manufacture a writable
view. An assignment such as `last().spindles[0] = value` remains invalid because
it would only mutate a temporary presentation and could not update the
component.

Both supported indexing forms follow this contract:

- a numeric member name such as `getMember("0")`;
- a dynamic unsigned-integer datasource used by scripting `array[index]`.

An out-of-range read retains the existing `internal::NA<T>::na()` behavior.

## Design

Add a focused read-only indexed-element datasource beside the existing
`ArrayPartDataSource<T>`. It stores:

- the readable `DataSource<types::carray<T> >` parent;
- the readable unsigned-integer index datasource;
- the array bound.

Each read evaluates the index and obtains the current read-only array view from
the parent before selecting the element. It does not expose `set()` and does not
derive from `AssignableDataSource<T>`.

The datasource keeps the parent alive. Its `clone()` retains the same parent and
index, matching the existing indexed datasource behavior. Its `copy()` copies
the parent and index through RTT's replacement map so copied expression graphs
do not retain references into the original graph.

`CArrayTypeInfo::getMember()` continues to prefer the existing
`ArrayPartDataSource<T>` when the parent is assignable. When the parent is only
readable, it creates the new read-only datasource. The same selection is used
for numeric-string and dynamic indexing.

No TaskBrowser or expression-parser change is required. Those layers already
handle a readable datasource returned by `getMember()`.

## Alternatives Rejected

Returning a `ConstantDataSource<T>` would be smaller, but it would freeze the
index and element value when the expression is built. RTT indexes are
datasources and may change while a program runs.

Converting `ArrayPartDataSource<T>` into a dual writable/read-only abstraction
would mix two different interfaces and put the established parent-update path
at risk. A separate read-only class keeps the change local.

Extending `BoostArrayTypeInfo` in the same change would broaden the regression
scope without a reported or reproduced Boost-array failure. It can be handled
separately if its read-only behavior is required.

## Tests

Add repository tests before production code and verify that they fail because
read-only C-array indexing currently returns a null datasource.

The direct type-discovery regression covers:

- numeric-string and dynamic indexing of a read-only C-array member;
- the expected element value;
- rejection of `AssignableDataSource<T>` narrowing;
- retained assignability for the equivalent writable C-array member;
- clone/copy behavior for the new read-only indexed datasource.

The scripting regression evaluates an indexed element beneath an
operation-return structure and verifies the value is readable. Existing tests
continue to cover invalid indexing and parser recovery; this change does not
claim to fix the separately reported, unreproduced deployer crash.

## Scope

Production changes are limited to RTT's indexed datasource support and
`CArrayTypeInfo`. Tests are limited to the corresponding RTT type-discovery and
scripting suites. There are no OCL, OPC UA, generated typekit, Boost-array, or
wire-format changes.
