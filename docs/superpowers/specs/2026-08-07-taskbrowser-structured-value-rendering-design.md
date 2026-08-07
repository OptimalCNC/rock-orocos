# TaskBrowser Structured Value Rendering Design

Date: 2026-08-07

## Status

Approved in discussion. This document defines the implementation contract for
bounded, named rendering of structured RTT values in OCL TaskBrowser.

## Context

TaskBrowser currently chooses a type's stream operator whenever the type is
streamable. Custom structures therefore appear in a type-specific positional
format such as:

```text
sample [U]> EnvelopeAttribute
 = Envelope{           Point{3, 4}, 5}
```

This output has two problems:

1. It does not show which value belongs to which member.
2. The field width installed by `TaskBrowser::printResult()` applies to the
   next stream insertion. A composite stream operator performs several
   insertions, so padding can appear inside the value after its first token.

RTT already exposes structure member names and indexed sequence access through
type metadata. TaskBrowser can use that metadata to render values consistently,
without changing each type's stream operator or the OPC UA wire format.

## Goals

- Render supported structures with member names.
- Render nested structures recursively.
- Keep small values compact and make larger values readable.
- Bound sequence, nesting, member, and total output size.
- Preserve type information that matters when reading scalar values, including
  a decimal marker for whole-valued floating-point numbers.
- Read a remote OPC UA value once, then inspect a local snapshot.
- Fail safely when a value or one of its members cannot be read.
- Preserve the existing representation for opaque types without usable member
  metadata.

## Non-goals

- No new `.type` or `.types <expression>` command.
- No change to the existing plural `.types` registry listing.
- No pager, interactive folding, or terminal tree widget.
- No RTT type-system, typekit, OPC UA object-model, or wire-format change.
- No production fixture type changes solely to demonstrate formatting.
- No attempt to publish, unpublish, reconcile, or replace OPC UA nodes.

## User-visible Contract

### Named structures

Small structures render on one line using member names and `:` separators:

```text
Deployer [S]> sample.EnvelopeAttribute
 = {point: {x: 3.0, y: 4.0}, quality: 5}
```

Type names such as `Envelope` and `Point` are not repeated in the value. The
expression path and member names provide the useful context, while `.types`
continues to list registered type names.

### Scalar leaves

Boolean, integral, character, and string leaves retain TaskBrowser's existing
scalar representation. Floating-point leaves must contain a decimal marker
when their value is mathematically integral, so `3.0` is not displayed as `3`.
Non-integral values retain their significant digits according to the existing
stream precision.

Hexadecimal mode continues to apply to integral scalar leaves. Structural
punctuation, indexes, member names, counts, and floating-point values remain in
their normal notation.

### Compact and multiline layout

The renderer first constructs a bounded compact candidate. It uses compact
layout only when the complete ` = <value>` result is at most 100 printable
characters and none of its children require multiline layout. Otherwise it
uses two-space indentation and places each structure member or sequence element
on its own line.

Example:

```text
Deployer [S]> sample.LargeAttribute
 = {
  header: {sequence: 42, enabled: true},
  points: [
    [0]: {x: 1.0, y: 2.0},
    [1]: {x: 3.0, y: 4.0},
    [2]: {x: 5.0, y: 6.0},
    ... 997 items omitted
  ],
  diagnostics: {
    temperatures: {
      motors: {...}
    }
  }
}
```

Layout is deterministic and does not depend on terminal width detection.

### Sequence preview

- An empty sequence renders as `[]`.
- A sequence with one to three elements renders all its elements.
- A sequence with more than three elements renders indexes `[0]`, `[1]`, and
  `[2]`, followed by `... N items omitted`.
- The renderer does not automatically include trailing elements.
- Users inspect an omitted element by evaluating its path, for example
  `sample.LargeAttribute.points[40]`.

The sequence's metadata members such as `size` and `capacity` are not repeated
as ordinary structure members in the rendered value.

### Structure limits

- The root value is structural depth 1.
- Structures and sequences expand through depth 3.
- A structure or sequence encountered at depth 4 renders as `{...}` or `[...]`
  respectively.
- At most 20 members of one structure are rendered, in metadata order.
- Additional members are represented by `... N members omitted`.

Users inspect an omitted subtree by evaluating its path, for example
`sample.LargeAttribute.diagnostics.temperatures`.

### Total output limit

One rendered value, excluding the interactive prompt but including the ` = `
prefix, is limited to 4096 bytes. The budget includes member names, formatting,
and scalar data such as large strings.

The renderer reserves enough space for all open delimiters and an explicit
omission marker. If the next complete item does not fit, it emits
`... output omitted` at that level and closes every open brace and bracket.
It never emits an unterminated structural value. A scalar leaf that alone
exceeds the remaining budget is rendered as a bounded prefix followed by
`... N bytes omitted`; the count describes bytes removed from that scalar's
existing stream representation.

## Architecture

### Rendering boundary

Add a focused structured-value renderer owned by OCL TaskBrowser. TaskBrowser
continues to parse and evaluate expressions; the renderer is responsible only
for converting one resulting data source into bounded text.

The renderer receives:

- the result data source;
- the current hexadecimal-mode setting;
- fixed rendering limits;
- an output stream or string result.

The renderer has no dependency on OPC UA classes. It works through RTT
`DataSourceBase` and `TypeInfo` APIs so local and remote TaskContexts follow the
same display path.

### Snapshot before traversal

For a value with usable member metadata, rendering follows this data flow:

```text
expression result data source
        |
        | TypeInfo::buildValue()
        v
local assignable snapshot
        |
        | snapshot->update(result)
        | exactly one root evaluation/read
        v
recursive local metadata traversal
        |
        v
bounded text
```

`snapshot->update(result)` is the only root evaluation performed by this path.
TaskBrowser must not call `result->evaluate()` first. This invariant matters for
OPC UA proxy data sources, where evaluating the source performs a network read.
It also prevents a structure member traversal from repeatedly reading or
writing the remote parent.

After the snapshot succeeds, all `getMember()` and indexed-member calls operate
on the local snapshot. Rendering never calls `set()`, `updated()`, or any source
mutation API.

### Opaque fallback

A value uses structural rendering only if a local snapshot can be built and
the type exposes usable structure or sequence metadata. Otherwise TaskBrowser
uses its current stream representation. Streamability alone does not override
usable member metadata; this is what allows named rendering of streamable
custom structures.

`RTT::PropertyBag` keeps its existing specialized TaskBrowser presentation.

### Recursive representation

The renderer classifies each local node as one of:

- structure: named members from RTT metadata;
- sequence: indexed access plus size metadata;
- scalar or opaque leaf: existing stream representation.

The recursive result carries both compact and multiline forms, byte cost,
whether truncation occurred, and whether the node requires multiline layout.
This lets a parent choose layout without evaluating a data source again.

Rendering constants are internal and fixed for this version:

| Limit | Value |
|---|---:|
| Compact result width | 100 printable characters |
| Sequence elements | 3 |
| Expanded structural depth | 3 |
| Members per structure | 20 |
| Total result size | 4096 bytes |
| Indentation | 2 spaces per level |

## Error Handling

- If the root snapshot update fails, TaskBrowser reports the existing expression
  evaluation error. It must not print `{}`, `[]`, or a partially initialized
  value as if the read succeeded.
- If one member cannot be resolved from an otherwise valid local snapshot, that
  member renders as `<unavailable>` and sibling rendering continues.
- Null member data sources are treated as unavailable.
- Unknown or opaque types retain the current stream representation.
- Empty structures render as `{}` and empty sequences as `[]`.
- Recursive rendering must not throw through the interactive TaskBrowser loop.
  Type or formatting failures are converted to the existing error path or an
  `<unavailable>` leaf as appropriate.
- All truncation is explicit, and every opened delimiter is closed.

## Testing

### Renderer unit tests

Add automated OCL TaskBrowser tests for:

1. Exact compact output for `Envelope`:
   `{point: {x: 3.0, y: 4.0}, quality: 5}`.
2. The multiline threshold and two-space indentation.
3. Whole-valued Float32 and Float64 leaves retaining `.0`.
4. Sequence sizes 0, 1, 3, 4, and a large sequence, including exact omitted
   counts and indexed element labels.
5. Structural depth 3 expanding and depth 4 collapsing.
6. A structure with more than 20 members and its exact omitted-member count.
7. The 4096-byte cap, including a single oversized string, with balanced
   delimiters and explicit omission markers.
8. An inaccessible member producing `<unavailable>` without hiding siblings.
9. An opaque streamable type retaining its existing representation.
10. Constants remaining read-only; rendering must not mutate or publish an
    update to the source.
11. A counting data source proving one and only one root evaluation for a
    structured render.

Tests compare plain output with terminal colors disabled.

### Installed acceptance test

Build and install OCL and the existing OPC UA custom-datatype fixture into a
fresh temporary prefix under `/tmp`. Use a temporary `HOME` and do not install
anything into `~/.orocos`.

Run `deployer-opcua` and `ctaskbrowser-opcua` as separate processes. Import the
fixture typekit before `opcua.start()`, load and publish the fixture component,
then verify through the client that:

- `sample.EnvelopeAttribute` has the exact named compact representation;
- nested member paths such as `sample.EnvelopeAttribute.point.x` still work;
- the remote root value is read once per expression;
- the client remains usable after rendering bounded large values.

## Compatibility

This intentionally changes the interactive textual representation of
structured values. Scripts must not parse TaskBrowser's human-oriented output
as a stable machine protocol. Expression syntax, RTT values, type names,
assignment behavior, and OPC UA transport data are unchanged.

## Acceptance Criteria

The change is complete when all renderer tests and the installed two-process
acceptance test pass from temporary prefixes, the one-root-read invariant is
demonstrated, output limits are deterministic, and no RTT, rtt_opcua,
open62541, or open62541pp source change is required.
