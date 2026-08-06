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
writable attributes, read-only constants, input ports, and output ports:

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

## Endpoint Lifecycle

The installed Deployer fixture executes this sequence:

```text
import("orocos_opcua_fixture")
loadComponent("sample", "orocos::opcua::fixture::FixtureComponent")
loadComponent("unsupported", "orocos::opcua::fixture::UnsupportedComponent")
opcua.start()
opcua.publishComponent("sample")
```

The runner first launches the same deployment without the last two commands
and proves that the TCP port remains closed and a remote Deployer proxy cannot
be created. It then starts a fresh process with the complete script and checks:

- `endpointUrl()` is configuration, while `isRunning()` reports a live
  listener plus complete Deployer publication;
- the remote `opcua` service has exactly six operations;
- whole-component publication includes every supported Deployer operation,
  including the `RTT::ConnPolicy` connection methods;
- publication is strict, static, and idempotent;
- an intentionally untransported type rejects the complete component with the
  exact resource diagnostic; and
- a published component cannot be unloaded in this version.

> [!IMPORTANT]
> Import all required typekits and OPC UA transport plugins before
> `opcua.start()`. The first start freezes the datatype registry for the rest of
> the process. `Server=true` does not cause OPC UA publication.

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

On 2026-08-05, the Task 6 release run passed end to end on Ubuntu 24.04 x86-64
with GCC 13.3 and CMake 3.28.3:

- RTT canonical typekit and scripting tests: 2/2
- `rtt_opcua`: 10/10
- OCL lifecycle and `ctaskbrowser-opcua` CLI tests: 11/11
- standalone server/client fixture: passed all seven representative types
- stopped and explicit-start Deployer process cases: passed
- strict unsupported publication and published-component unload rejection:
  passed
- installed metadata and dynamic linkage: no resolved artifact below
  `~/.orocos`

The maintained install is `/tmp/orocos-opcua-task6-final.2tFntH`; logs, CMake
caches, the generated manual runtime environment, and `ldd` records are in
`/tmp/orocos-opcua-task6-final.2tFntH-work`.

This gate uses unmodified open62541 v1.4.15 and open62541pp v0.21.2 artifacts.
It does not build their unit tests. Fresh sanitizer, detached-tag dependency,
manual TaskBrowser, and package-wide results belong to the Task 8 verification
gate and are not claimed here.

Target Xenomai validation, cross-distribution CI, and downstream migration
steps 9 through 13 remain separate gates.
