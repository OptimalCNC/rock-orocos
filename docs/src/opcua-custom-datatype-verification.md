# OPC UA Custom Datatype Verification

The generic custom-datatype delivery is verified without MetaNC and without
installing or resolving artifacts from `~/.orocos`. The verification runner
rebuilds and installs RTT, `rtt_opcua`, and OCL into a required empty prefix
below `/tmp`, then builds an external fixture solely against that installed
prefix.

## Covered Contract

The fixture is a separate RTT typekit and OPC UA transport plugin. It registers
`Point`, nested `Envelope`, and `PointArray` under the provider namespace
`urn:orocos:rtt:fixture`. Its server and client run in separate processes and
explicitly load both fixture plugins before constructing an OPC UA endpoint.

The test round-trips these types through operations, writable properties,
writable attributes, input ports, and output ports:

- `Float64Array`
- `Int32Array`
- `StringArray`
- `RtString`
- `/orocos/fixture/Point`
- `/orocos/fixture/Envelope`
- `/orocos/fixture/PointArray`

It also verifies custom DataType and binary-encoding nodes by namespace URI and
stable string NodeId, forces the provider namespace away from index `1`, and
requires an empty unsupported-resource report.

## Running The Verification

The dependency prefix must be below `/tmp` and already contain farbot,
rtlog-cpp, open62541, and open62541pp. The install prefix must not exist or must
be empty, and its sibling `-work` directory must not exist before the run.

```bash
env -u OROCOS_PREFIX -u OROCOS_TARGET -u LD_LIBRARY_PATH \
    -u RTT_COMPONENT_PATH -u CMAKE_PREFIX_PATH -u PKG_CONFIG_PATH \
    -u RUBYLIB \
    JOBS=2 \
    ./tools/test-opcua-custom-datatypes.sh \
      --prefix /tmp/orocos-opcua-verification/prefix \
      --dependency-prefix /tmp/orocos-opcua-dependencies/prefix \
      --target gnulinux
```

The sanitizer run uses a different empty prefix:

```bash
env -u OROCOS_PREFIX -u OROCOS_TARGET -u LD_LIBRARY_PATH \
    -u RTT_COMPONENT_PATH -u CMAKE_PREFIX_PATH -u PKG_CONFIG_PATH \
    -u RUBYLIB \
    JOBS=2 \
    CXXFLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer' \
    LDFLAGS='-fsanitize=address,undefined' \
    ASAN_OPTIONS='detect_leaks=1:halt_on_error=1' \
    UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1' \
    ./tools/test-opcua-custom-datatypes.sh \
      --prefix /tmp/orocos-opcua-verification-sanitizer/prefix \
      --dependency-prefix /tmp/orocos-opcua-dependencies/prefix \
      --target gnulinux
```

The runner gives every build and test a temporary `HOME`, disables the CMake
user package registry, rejects a home Orocos prefix, records dynamic-library
resolution, and scans build caches, installed metadata, logs, and `ldd` output
for accidental resolution from the real `~/.orocos`.

## Current Evidence

On 2026-08-04, the final release run passed end to end on Ubuntu 24.04 x86-64
with GCC 13.3 and CMake 3.28.3:

- RTT canonical typekit test: 1/1 in 0.03 seconds
- `rtt_opcua`: 10/10 in 7.83 seconds
- OCL OPC UA deployment and CLI subset: 6/6 in 4.94 seconds
- external server/client fixture: passed all seven representative types
- installed metadata and dynamic linkage: no resolved artifact below
  `~/.orocos`

The fresh release install is
`/tmp/orocos-opcua-installed-fixture-release-final-20260803/prefix`;
supporting logs, CMake caches, and `ldd` records are in the sibling
`prefix-work` directory.

The ASan/UBSan/LSan verification used
`/tmp/orocos-opcua-installed-fixture-sanitizer-complete-20260803/prefix`.
RTT passed 1/1 in 0.47 seconds, `rtt_opcua` passed 10/10 in 10.35 seconds,
OCL passed 6/6 in 9.44 seconds, and the external fixture's server and client
both exited without sanitizer findings. That run found and fixed two harness
issues: the installed package-specific plugin directory was missing from the
temporary runtime path, and the fixture processes bypassed RTT's ordered
shutdown by using plain `main` instead of `ORO_main`.

The prerequisite stack was also checked directly. The patched
`open62541pp v0.21.2` suite passed 225/225 under ASan/UBSan/LSan, and the
patched `open62541 v1.4.15` attribute suite passed 31/31 under the same
sanitizers. These regressions cover string NodeId ownership, server custom
datatype teardown, and temporary `DataTypeDefinition` encoding identifiers.

GCC still emits `-Wmaybe-uninitialized` diagnostics from Boost.Spirit Classic
headers while compiling optimized sanitizer RTT tests. Changed maintained
targets compile with strict warnings as errors; no project-source warning
remains in this gate.

Target Xenomai validation and cross-distribution CI remain separate platform
gates. MetaNC migration steps 9 through 13 are not exercised by this generic
fixture.
