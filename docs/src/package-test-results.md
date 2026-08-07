# Package Test Results

This page records the package-level test status while the workflow is
experimental and non-required.

The package-test workflow runs on Ubuntu 22.04, Ubuntu 24.04, and Debian
13/Trixie. It keeps `continue-on-error: true` while cross-distribution legacy
package behavior is being classified. Package test steps return their real
exit status.

## CI Matrix Status

The established package-test entries use the public maintenance branches in
`autoproj/overrides.yml`. The OPC UA entry has local coverage and is awaiting
its first cross-distribution CI run.

| Package test | Required subset | Current status |
|---|---|---|
| `utilmm` | `Suite` from `utilmm_testsuite` | Passes in CI after fixes on `liufang-robot/utilmm` `dev`. |
| `typelib-cxx` | `CxxSuiteInstalledPlugins` and `CxxSuiteLocalPlugins` | Passes in CI after fixes on `liufang-robot/tools-typelib` `dev`. |
| `rtt-typelib` | Rebuilds `rtt-typelib`, runs `get_marshaller_for_test`, and checks `rtt_typelib-gnulinux` metadata | Passes in CI after fixes on `liufang-robot/tools-rtt_typelib` `dev`. |
| `rtt-core` | `main-test`, `list-test`, `core-test`, `task-test`, `mqueue-test`, and `mqueue_archive_test` | Existing CI evidence covers the core/task subset after scheduler-capability fixes on `liufang-robot/rtt` `dev`; the maintained contract configures mqueue with CORBA disabled. |
| `rtt-opcua` | All `rtt_opcua_*_test` and split `ocl_opcua_deployment_*` cases, OPC UA deployer/browser targets, and `rtt_opcua-gnulinux` plus OCL pkg-config metadata | Passes the local loopback installed-prefix gate; cross-distribution CI remains pending. |
| `ocl-basic` | `timer` and `taskb` | Passes in CI after standalone CTest fixes on `liufang-robot/ocl` `dev`. |
| `ocl-integration` | `deploy`, `testlogging`, `report`, `tcpreport`, and optional `ncreport` | Passes in CI on `dev`; `ncreport` is optional when NetCDF is unavailable, and the interactive state-machine browser remains outside this subset. |

## Fresh Verification Status

| Surface | Task 8 result |
|---|---|
| Source and dependency revision audit | Passed at root `652ad0637d68c3e228ac298099445cdc3d1aa67b`, RTT `f529ac1d7c2ea74242883df91fafa599fcc208b8`, `rtt_opcua` `f993906c251497af06e24c005ee4f9ee938203af`, and OCL `fb018446af77d52c8a9466275cda984ce8f12ca2`. |
| Warning-clean maintained package builds | Passed with GCC 13.3, CMake 3.28.3, C++20, CORBA disabled, and `rtt_opcua` warnings treated as errors. |
| Maintained package tests | RTT 2/2, `rtt_opcua` 10/10, and OCL lifecycle plus browser CLI 11/11 passed. |
| Sanitizer tests | `rtt_opcua` 10/10 and OCL lifecycle 6/6 passed under AddressSanitizer and UndefinedBehaviorSanitizer, with LeakSanitizer suppressing only two reproduced stock dependency allocation frames. |
| Installed standalone and Deployer fixture | Passed separate-process custom datatype round trips, stopped-endpoint rejection, explicit startup, complete Deployer publication, strict component publication, and unload protection. |
| Manual `ctaskbrowser-opcua` validation | Passed writable `Gain` and `Status`, `echo(42)`, read-only `Limit`, exact six-operation `opcua` service, and absence of the rejected unsupported component. |
| Home-prefix and CORBA contamination checks | Passed: the isolated home has no `.orocos`, and maintained `ldd`, logs, caches, and installed metadata resolve neither `~/.orocos` nor CORBA/OmniORB. |

The verified stock dependency revisions are open62541 v1.4.15
`45e4cd3ef6c79a8e503d37c9f5c89fefe90d99db` and open62541pp v0.21.2
`b1696768b26a12d0f40fdac5ec62ad78d25fa236`. Their sources were clean and
unchanged. `UA_BUILD_UNIT_TESTS` and `UAPP_BUILD_TESTS` were both `OFF`; no
third-party test suite was built or run.

The release install is `/tmp/orocos-opcua-maintained-final-review.LUHwJa`, with
build evidence in `/tmp/orocos-opcua-maintained-final-review.LUHwJa-work`.
Detached sources, the stock dependency prefix, sanitizer builds, raw and
filtered sanitizer logs, manual transcripts, and the final mdBook are below
`/tmp/orocos-opcua-task8.iaxbIP`.

The raw LeakSanitizer run identifies allocations rooted only in unchanged stock
open62541pp `opcua::detail::allocNativeString` and open62541 `UA_Array_copy`.
The passing sanitizer matrix uses a two-frame suppression file so all other
leaks and every AddressSanitizer or UndefinedBehaviorSanitizer error remain
fatal. In particular, the immediate shutdown after an operation timeout case
ran and retained the invocation until completion. The server test also proves
that concurrent `start()` callers share one serialized startup. Loader records
confirm that the `rtt_opcua` and OCL sanitizer tests use their build-tree
libraries rather than installed release copies.

The verification contract uses unmodified stock open62541 and open62541pp
sources and does not build third-party unit tests. A non-returning RTT operation
can still delay endpoint shutdown indefinitely because its lease and invocation
storage must not be released early. Target Xenomai validation,
cross-distribution CI, downstream application migration, and OPC UA PubSub port
mapping remain separate gates.
