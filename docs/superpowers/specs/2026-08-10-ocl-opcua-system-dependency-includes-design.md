# OCL OPC UA System Dependency Includes Design

**Date:** 2026-08-10

## Context

After the reviewed `rtt_opcua` dependency boundary built and installed, the
same clean C++20 Xenomai build stopped in OCL's `ctaskbrowser-opcua` target.
The preserved OCL log contains 67 promoted diagnostics: 66 originate below
`/usr/xenomai/include`, one originates in installed RTT's Xenomai `fosi.h`,
and none originate in maintained OCL code.

Both OCL OPC UA executables, `deployer-opcua` and `ctaskbrowser-opcua`, compile
with `-std=c++20 -Wall -Wextra -Wpedantic -Werror`. Both currently receive
`${RTT_OPCUA_INCLUDE_DIRS}` as ordinary target includes. The dependency list
contains installed `rtt_opcua`, Orocos RTT, and Xenomai include paths, so the
strict maintained-source policy is also applied to dependency implementation
details.

## Goal

Keep strict C++20 warnings for OCL's maintained OPC UA executable sources
while compiling installed `rtt_opcua`, Orocos RTT, and Xenomai 3.3.3 headers
through a target-local CMake system-include boundary.

## Non-Goals

- Do not disable or weaken `-Wall -Wextra -Wpedantic -Werror` on either OCL
  OPC UA executable.
- Do not add warning-specific suppressions for Xenomai diagnostics.
- Do not modify `rtt_opcua`, Orocos RTT, Xenomai, or installed headers for this
  issue.
- Do not change Orocos RTT or pkg-config metadata globally.
- Do not run a source update while resuming the installation.

## Design

The existing `target_include_directories` calls for `deployer-opcua` and
`ctaskbrowser-opcua` will classify `${RTT_OPCUA_INCLUDE_DIRS}` as
`SYSTEM PRIVATE`.

`PRIVATE` matches the executable boundary: neither target exports an include
contract to consumers. `SYSTEM` tells CMake that diagnostics originating in
the installed OPC UA, RTT, and Xenomai dependency paths do not belong to OCL's
maintained-source warning policy. CMake will de-duplicate paths also supplied
by the Orocos executable helper and emit the target-owned dependency paths as
system includes.

OCL's source directory, generated directory, and binary-directory includes
remain ordinary. The existing C++20 and strict warning options remain
unchanged for both translation units.

The change is limited to the two OPC UA executable targets in
`toolchain/tools/ocl/bin/CMakeLists.txt`. Other OCL targets and the reviewed
uncommitted `rtt_opcua` CMake change are outside its scope.

## Alternatives Considered

### Disable warnings as errors

Removing `-Werror` from the OPC UA executables would allow dependency warnings
but also stop enforcing warning-free maintained OCL code.

### Suppress individual warning classes

Adding `-Wno-error=pedantic`, `-Wno-error=unused-parameter`, and
`-Wno-error=variadic-macros` would couple OCL to the current Xenomai diagnostic
set and would also relax matching diagnostics in OCL code.

### Change exported RTT metadata

Reclassifying dependencies in Orocos RTT or pkg-config metadata would alter
the compile boundary for all consumers. The defect is limited to two strict
OCL executables and has a direct target-local representation.

## Verification

The preserved failed OCL build is the RED integration case. After the CMake
change:

1. Reconfigure OCL without changing its C++20 or warning policy.
2. Parse `compile_commands.json` structurally for both `deployer-opcua` and
   `ctaskbrowser-opcua` translation units.
3. Verify each command retains `-std=c++20 -Wall -Wextra -Wpedantic -Werror`.
4. Verify OCL source and generated include paths remain ordinary.
5. Verify installed `rtt_opcua`, Orocos RTT, and all Xenomai paths are system
   includes in both commands.
6. Build both OPC UA executable targets with strict warnings enabled.
7. Resume the single no-update Autoproj build, export the fresh environments,
   and run the installed-prefix validator.

If either focused target still fails, preserve the new first-failure log and
return to root-cause analysis rather than weakening warning policy or changing
a second source boundary.

## Preservation Contract

The implementation must leave OCL at synchronized HEAD
`d465bb83f6870503a53571a93a36adf01a8cdfc1` with only the approved CMake diff
visible and uncommitted. It must preserve the reviewed `rtt_opcua` CMake diff,
the intentional two-file RTT wakeup patch, both RTT stashes, and every selected
package ref. Root changes are limited to approved design and implementation
plan documentation; generated build and prefix artifacts remain untracked.
