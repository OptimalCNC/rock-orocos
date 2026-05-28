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
`liufang-robot/*` maintenance forks on their `dev` branches.

| Package test | Initial subset | Current status |
|---|---|---|
| `utilmm` | `Suite` CTest case from `utilmm_testsuite` | Passes in CI after stabilizing socket, shell expansion, and pkg-config flag-order tests on `liufang-robot/utilmm` `dev`. |
| `log4cpp` | Existing CTest tests | Passes in CI after C++17 warning cleanup on `liufang-robot/log4cpp` `dev`. |
| `typelib-cxx` | `CxxSuiteInstalledPlugins` and `CxxSuiteLocalPlugins` | Passes in CI after Ruby/C++ extension warning cleanup on `liufang-robot/tools-typelib` `dev`. |
| `rtt-core` | `main-test`, `list-test`, `core-test`, and full `task-test` | Passes in CI after making RTT task thread tests scheduler-capability aware on `liufang-robot/rtt` `dev`. CORBA and mqueue tests stay out of this subset. |
| `ocl-basic` | `timer` and `taskb` | Passes in CI after restoring OCL standalone CTest support on `liufang-robot/ocl` `dev`. Deployment, reporting, and logging tests stay out of this subset. |
| `ocl-integration` | `deploy`, `testlogging`, `report`, `tcpreport`, and `ncreport` | Passes in CI on `liufang-robot/ocl` `dev`. The interactive `testWithStateMachine` TaskBrowser case stays out of the CI subset until it has a non-interactive harness. |

Deferred test groups:

- oroGen Ruby tests, until Ruby test dependencies such as `flexmock/minitest`
  are explicitly staged.
- RTT CORBA, mqueue, and transport-sensitive tests, until their runtime
  assumptions are documented.
