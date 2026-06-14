# Package Test Results

This page records the package-level test status while the workflow is
experimental and non-required.

The package-test workflow runs on Ubuntu 22.04, Ubuntu 24.04, and Debian
13/Trixie. It keeps `continue-on-error: true` while cross-distribution legacy
package test behavior is being classified. Package test steps return their real
exit status.

## CI Matrix Status

The latest package-test matrix passes on Ubuntu 22.04, Ubuntu 24.04, and
Debian 13/Trixie. The package source overrides use the public
`OptimalCNC/*` maintenance forks on their `dev` branches.

| Package test | Initial subset | Current status |
|---|---|---|
| `utilmm` | `Suite` CTest case from `utilmm_testsuite` | Passes in CI after stabilizing socket, shell expansion, and pkg-config flag-order tests on `OptimalCNC/utilmm` `dev`. |
| `log4cpp` | Existing CTest tests | Passes in CI after C++17 warning cleanup on `OptimalCNC/log4cpp` `dev`. |
| `typelib-cxx` | `CxxSuiteInstalledPlugins` and `CxxSuiteLocalPlugins` | Passes in CI after Ruby/C++ extension warning cleanup on `OptimalCNC/tools-typelib` `dev`. |
| `rtt-typelib` | Rebuilds `rtt-typelib`, runs `get_marshaller_for_test`, and checks `rtt_typelib-gnulinux` pkg-config metadata | Passes in CI after adding marshaller lookup coverage on `OptimalCNC/tools-rtt_typelib` `dev`. |
| `stdint-typekit` | Rebuilds `stdint-typekit` and checks `stdint-gnulinux` pkg-config metadata | Build/smoke gate for `OptimalCNC/stdint_typekit` `dev`; no package CTest suite is currently defined. |
| `rtt-core` | `main-test`, `list-test`, `core-test`, and full `task-test` | Passes in CI after making RTT task thread tests scheduler-capability aware on `OptimalCNC/rtt` `dev`. CORBA and mqueue tests stay out of this subset. |
| `ocl-basic` | `timer` and `taskb` | Passes in CI after restoring OCL standalone CTest support on `OptimalCNC/ocl` `dev`. Deployment, reporting, and logging tests stay out of this subset. |
| `ocl-integration` | `deploy`, `testlogging`, `report`, `tcpreport`, and optional `ncreport` when NetCDF support is available | Passes in CI on `OptimalCNC/ocl` `dev`. The interactive `testWithStateMachine` TaskBrowser case stays out of the CI subset until it has a non-interactive harness. |

Pinned `log4cpp` CTest subset:

- `testCategory`
- `testFixedContextCategory`
- `testNDC`
- `testPattern`
- `testErrorCollision`
- `testPriority`
- `testFilter`
- `testProperties`
- `testConfig`
- `testPropertyConfig`
- `testRollingFileAppender`
- `testDailyRollingFileAppender`

Deferred test groups:

- oroGen Ruby tests, until Ruby test dependencies such as `flexmock/minitest`
  are explicitly staged.
- RTT CORBA, mqueue, and transport-sensitive tests, until their runtime
  assumptions are documented.
