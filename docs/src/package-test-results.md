# Package Test Results

This page records the package-level test status while the workflow is
experimental and non-required.

The package-test workflow runs on Ubuntu 22.04, Ubuntu 24.04, and Debian
13/Trixie. It keeps `continue-on-error: true` while cross-distribution legacy
package test behavior is being classified. Package test steps return their real
exit status.

## CI Matrix Status

The established package-test matrix entries pass on Ubuntu 22.04, Ubuntu
24.04, and Debian 13/Trixie. The new `rtt-opcua` entry has local coverage and
is awaiting its first cross-distribution CI run. Package source overrides use
the public maintenance forks and branch pins recorded in
`autoproj/overrides.yml`.

| Package test | Initial subset | Current status |
|---|---|---|
| `utilmm` | `Suite` CTest case from `utilmm_testsuite` | Passes in CI after stabilizing socket, shell expansion, and pkg-config flag-order tests on `liufang-robot/utilmm` `dev`. |
| `typelib-cxx` | `CxxSuiteInstalledPlugins` and `CxxSuiteLocalPlugins` | Passes in CI after Ruby/C++ extension warning cleanup on `liufang-robot/tools-typelib` `dev`. |
| `rtt-typelib` | Rebuilds `rtt-typelib`, runs `get_marshaller_for_test`, and checks `rtt_typelib-gnulinux` pkg-config metadata | Passes in CI after adding marshaller lookup coverage on `liufang-robot/tools-rtt_typelib` `dev`. |
| `rtt-core` | `main-test`, `list-test`, `core-test`, and full `task-test` | Passes in CI after making RTT task thread tests scheduler-capability aware on `liufang-robot/rtt` `dev`. CORBA and mqueue tests stay out of this subset. |
| `rtt-opcua` | All `rtt_opcua_*_test` cases, `ocl_opcua_deployment_test`, the OPC UA deployer/browser targets, and `rtt_opcua-gnulinux` pkg-config metadata | Locally passes with loopback client/server sockets against the temporary installed prefix. The public `liufang-robot/rtt_opcua` repository now exists; its first cross-distribution CI result remains pending. |
| `ocl-basic` | `timer` and `taskb` | Passes in CI after restoring OCL standalone CTest support on `liufang-robot/ocl` `dev`. Deployment, reporting, and logging tests stay out of this subset. |
| `ocl-integration` | `deploy`, `testlogging`, `report`, `tcpreport`, and optional `ncreport` when NetCDF support is available | Passes in CI on the selected OCL maintenance branch. The interactive `testWithStateMachine` TaskBrowser case stays out of the CI subset until it has a non-interactive harness. |

The stable source policy follows each maintenance fork's default branch in
`autoproj/overrides.yml`: `farbot` uses `master`, `rtlog-cpp` uses `main`, and
the RTT, OCL, generator, and OPC UA packages use `dev`.

## C++20 and OPC UA Modernization Verification

The modernization worktree was verified locally on Ubuntu 24.04 x86-64 with
GCC 13.3 and CMake 3.28. All C++ targets were compiled as C++20 with
`-Wall -Wextra -Wpedantic -Werror`.

| Package | Verification result |
|---|---|
| RTT release | Full rebuild and all 44 CTest cases passed in 223.56 seconds. CORBA was configured `OFF`. |
| RTT sanitizers | Full Debug rebuild and all 44 CTest cases passed in 243.71 seconds with AddressSanitizer, UndefinedBehaviorSanitizer, LeakSanitizer, and strict ODR violation detection enabled. Build-tree typekits and plugins are staged as links to their canonical targets so the loader cannot map a second copy of an already-linked library. |
| RTT scripting | The program/parser suites and all eight parser corpus seeds passed in release and sanitizer builds. Coverage includes rejection of adjacent operation calls without a statement separator. |
| `rtt_opcua` | All five CTest cases passed in 5.53 seconds against `open62541pp v0.21.2` and `open62541 v1.4.15` from the isolated temporary prefix. The same five cases passed in 7.09 seconds with AddressSanitizer, UndefinedBehaviorSanitizer, and LeakSanitizer enabled. Coverage includes immediate model shutdown after an OwnThread operation timeout. |
| OCL | All 11 registered CTest cases passed in 4.10 seconds after explicitly rebuilding their executable targets and installing RTT/OCL into the isolated temporary prefix. This includes `testWithStateMachine`, canonical Lua scalar names, and OPC UA deployment coverage proving that one `publishPeer` call exposes the component's complete supported RTT interface. The OPC UA deployment library, deployer, and TaskBrowser client compiled with `-Wall -Wextra -Wpedantic -Werror`. |
| oroGen | The complete no-CORBA generator matrix passed: 89 tests and 312 assertions. It covers generated C++20 task code, typekits, typegen regeneration, the self-contained RTT scalar/array model, and removed-type lookup. Thirteen tests whose names or fixtures explicitly require CORBA remain outside the required matrix. |
| Installed tools | `deployer-opcua-gnulinux --help` exposes the loopback-only address, port, and endpoint-path options; `ctaskbrowser-opcua-gnulinux --help` exposes the remote endpoint/component syntax. |

The builds, tests, and installs used isolated directories under `/tmp`, with a
temporary `HOME` and install prefix. The final verification environment set
its executable, library, pkg-config, CMake, Ruby, and RTT component paths
explicitly so that none referenced `~/.orocos`. The installed RTT and OCL libraries,
executables, pkg-config metadata, and runtime dependencies contain no
CORBA/omniORB artifacts and do not resolve libraries from `~/.orocos`. OroGen
retains its generic CORBA source templates, consistent with keeping CORBA
source present while the selected RTT and OCL builds remain disabled.

Clang is not installed in the local verification environment, so the
libFuzzer mutation target was not run. The same shared parser harness and its
seed corpus passed under GCC with the sanitizers listed above.

Deferred test groups:

- oroGen tests whose transport sets or deployment fixtures explicitly require
  CORBA. The no-CORBA generator matrix stages `flexmock/minitest` in `/tmp`.
- RTT CORBA and target-specific transport tests that are unavailable in the
  local `gnulinux` no-CORBA configuration.
