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

The installed Deployer fixture also exposes a built-in `Int32` `Gain`
property, writable `String` `Status` attribute, read-only `Int32` `Limit`
constant, and `echo(Int32)` operation. These make the expected remote
assignability rules directly testable in `ctaskbrowser-opcua`.

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

Sanitizer verification uses fresh Debug build trees for owned `rtt_opcua` and
OCL code after the release prefix has been installed. The exact configuration
is in Task 8 of the
[OPC UA Static Publication Implementation Plan](./opcua-deployer-lifecycle-plan.md).
Run LeakSanitizer once without suppressions. A suppression is acceptable only
after its stack has been reproduced in an unchanged pinned dependency; owned
callback state, invocation lifetime, hangs, and every other leak remain fatal.

The runner gives every build and test a temporary `HOME`, disables the CMake
user package registry, rejects a home Orocos prefix, records dynamic-library
resolution, and scans build caches, installed metadata, logs, and `ldd` output
for accidental resolution from the real `~/.orocos`.

## Current Evidence

The 2026-08-05 Task 8 gate passed on Ubuntu 24.04 x86-64 with GCC 13.3.0 and
CMake 3.28.3. The exact verified source revisions are:

| Source | Revision |
|---|---|
| `orocos-rock` implementation | `d447800aa9b119f279624041f2b760e4e5e04609` |
| RTT | `f529ac1d7c2ea74242883df91fafa599fcc208b8` |
| `rtt_opcua` | `a94eee231fcae55ec8cc8774817e747d9ffd58d1` |
| OCL | `fb018446af77d52c8a9466275cda984ce8f12ca2` |
| farbot | `09fd406eef4778511e85b569e3e75cad3d5cf608` |
| rtlog-cpp | `5842ca36c69ad4ba34321eda80891c832298f161` |
| open62541 v1.4.15 | `45e4cd3ef6c79a8e503d37c9f5c89fefe90d99db` |
| open62541pp v0.21.2 | `b1696768b26a12d0f40fdac5ec62ad78d25fa236` |

The dependency sources were detached, clean, and unchanged. open62541 used
shared libraries, reduced namespace zero, PubSub disabled, examples disabled,
and `UA_BUILD_UNIT_TESTS=OFF`. open62541pp used shared libraries, the external
open62541 installation, examples and documentation disabled, and
`UAPP_BUILD_TESTS=OFF`. No dependency unit tests were built or run.

The fresh maintained matrix passed:

- RTT canonical typekit and scripting tests: 2/2 in 0.28 seconds;
- `rtt_opcua`: 10/10 in 8.73 seconds;
- OCL lifecycle and `ctaskbrowser-opcua` CLI tests: 11/11 in 4.59 seconds;
- standalone server/client round trips for all seven representative types;
- closed listener and rejected Deployer proxy before `opcua.start()`;
- explicit-start Deployer, strict publication, unsupported-type rollback, and
  published-component unload rejection; and
- warning-clean C++20 builds with CORBA disabled and no maintained artifact
  resolved from `~/.orocos`.

The manual browser connected to the installed sample and changed `Gain` from
`1` to `9` and `Status` from `idle` to `running`. `echo(42)` returned `42`.
Assigning `Limit = 101` produced the expected constant-assignment error and a
subsequent read remained `100`. The remote Deployer exposed exactly `start`,
`isRunning`, `endpointUrl`, `lastError`, `publishComponent`, and
`unsupportedResources`. Strict publication of the intentionally unsupported
component returned false, reported its missing protocol, and left no remotely
browsable component node.

Fresh AddressSanitizer and UndefinedBehaviorSanitizer builds passed
`rtt_opcua` 10/10 in 9.92 seconds and the six OCL lifecycle cases in 5.49
seconds. The immediate-shutdown-after-timeout case ran explicitly and retained
the asynchronous invocation through completion. An unsuppressed LeakSanitizer
run found only two stack roots in the unchanged stock dependencies:
open62541pp `opcua::detail::allocNativeString` and open62541 `UA_Array_copy`
while reading a datatype definition. The passing matrix suppresses only those
two frames; every other leak and all ASan/UBSan findings remain fatal. No
third-party source was patched.

The release install is `/tmp/orocos-opcua-maintained-final.z5XQfT`, and its
build trees, runtime environment, logs, caches, and `ldd` records are in
`/tmp/orocos-opcua-maintained-final.z5XQfT-work`. Detached sources, dependencies,
sanitizer evidence, manual transcripts, and the final mdBook are below
`/tmp/orocos-opcua-task8.iaxbIP`.

A non-returning OwnThread operation can delay shutdown indefinitely; releasing
its component lease or invocation storage early would be unsafe. Target
Xenomai validation, cross-distribution CI, downstream migration steps 9 through
13, PKI/non-loopback security, unpublication, and OPC UA PubSub port mapping
remain separate future gates.
