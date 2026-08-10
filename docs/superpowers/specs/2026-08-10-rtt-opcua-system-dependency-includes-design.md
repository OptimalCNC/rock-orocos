# RTT OPC UA System Dependency Includes Design

**Date:** 2026-08-10

## Context

The clean C++20 Xenomai build enables
`RTT_OPCUA_WARNINGS_AS_ERRORS=ON` for `rtt_opcua`. The package correctly
builds its maintained sources with `-Wall -Wextra -Wpedantic -Werror`, but its
current CMake include boundary also classifies Orocos RTT and Xenomai headers
as ordinary project includes.

With Xenomai 3.3.3, that boundary promotes dependency diagnostics for GNU
extensions and unused parameters to errors. The first failed build recorded
201 diagnostics: 198 originated below `/usr/xenomai/include` and three in the
installed RTT Xenomai `fosi.h`; none originated in a maintained `rtt_opcua`
source file.

## Goal

Keep warnings as errors for maintained `rtt_opcua` code while allowing the
selected Orocos RTT and Xenomai dependency headers to compile under GCC 13 and
C++20 without changing or suppressing their source.

## Non-Goals

- Do not disable `RTT_OPCUA_WARNINGS_AS_ERRORS` in the Autoproj build.
- Do not remove `-Wall`, `-Wextra`, or `-Wpedantic` from maintained sources.
- Do not add warning-specific suppressions for Xenomai 3.3.3 diagnostics.
- Do not modify Orocos RTT, Xenomai, or their installed headers for this issue.
- Do not update any source checkout while resuming the installation.

## Design

`rtt_opcua` will keep its own build and install include directories in the
existing ordinary `PUBLIC` include set. Its `${OROCOS-RTT_INCLUDE_DIRS}` will
move to a separate `SYSTEM PUBLIC` target include declaration.

This preserves the public dependency relationship required by installed
`rtt_opcua` headers while telling CMake that diagnostics originating in Orocos
RTT and its Xenomai include paths belong to dependencies. GCC will continue to
apply the package's strict warning flags to `rtt_opcua` translation units and
ordinary project headers.

The change is limited to the `orocos-rtt-opcua` target. The transport plugin
inherits the dependency boundary by linking the library and keeps its own
project include directory ordinary.

## Alternatives Considered

### Disable warnings as errors

Setting `RTT_OPCUA_WARNINGS_AS_ERRORS=OFF` would allow the build, but it would
weaken the repository's maintained-source quality gate and contradict the
existing Autoproj policy.

### Suppress individual warnings

Adding `-Wno-error=variadic-macros`, `-Wno-error=unused-parameter`, and
`-Wno-error=pedantic` would couple `rtt_opcua` to the current Xenomai diagnostic
set. New dependency warnings would fail again, while matching warnings in
maintained code would no longer be errors.

### Patch dependency headers

Editing Xenomai or installed RTT headers would expand ownership beyond this
workspace package and create a maintenance fork for behavior that CMake's
system-include boundary already models directly.

## Verification

The preserved clean-build failure is the RED integration case. After the
CMake change:

1. Reconfigure `rtt_opcua` with C++20 and
   `RTT_OPCUA_WARNINGS_AS_ERRORS=ON`.
2. Verify the generated compile command retains `-std=c++20`,
   `-Wall -Wextra -Wpedantic -Werror`, and an ordinary include path for the
   package's own `include/` directory.
3. Verify Orocos RTT and Xenomai dependency paths are emitted as system
   includes.
4. Build and install `rtt_opcua`; any diagnostic from maintained source must
   still fail the build.
5. Resume the existing Autoproj build without a source update, export the
   fresh prefix environments, and run the installed-prefix validator.

If the focused build still fails, preserve the new first-failure log and
return to root-cause analysis instead of adding broader warning suppressions.

## Preservation Contract

The implementation must not modify the intentional uncommitted RTT wakeup
patch, either retained RTT stash, or synchronized package refs. The
`rtt_opcua` compatibility change remains visible in its nested checkout for
review and later publication; generated build and prefix artifacts remain
untracked installation state. Root changes are limited to the approved design
and implementation-plan documentation.
