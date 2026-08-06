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
| `rtt-core` | `main-test`, `list-test`, `core-test`, and `task-test` | Passes in CI after scheduler-capability fixes on `liufang-robot/rtt` `dev`; CORBA and mqueue tests remain outside this subset. |
| `rtt-opcua` | All `rtt_opcua_*_test` and split `ocl_opcua_deployment_*` cases, OPC UA deployer/browser targets, and `rtt_opcua-gnulinux` plus OCL pkg-config metadata | Passes the local loopback installed-prefix gate; cross-distribution CI remains pending. |
| `ocl-basic` | `timer` and `taskb` | Passes in CI after standalone CTest fixes on `liufang-robot/ocl` `dev`. |
| `ocl-integration` | `deploy`, `testlogging`, `report`, `tcpreport`, and optional `ncreport` | Passes in CI on `dev`; `ncreport` is optional when NetCDF is unavailable, and the interactive state-machine browser remains outside this subset. |

## Fresh Verification Status

> [!IMPORTANT]
> Exact package totals, timings, sanitizer results, and detached dependency tag
> revisions will be recorded only after the fresh Task 8 verification. Older
> local pass counts are intentionally not carried forward as current evidence.

| Surface | Task 8 result |
|---|---|
| Source and dependency revision audit | Pending |
| Warning-clean maintained package builds | Pending |
| Maintained package tests | Pending |
| Sanitizer tests | Pending |
| Installed standalone and Deployer fixture | Pending |
| Manual `ctaskbrowser-opcua` validation | Pending |
| Home-prefix and CORBA contamination checks | Pending |

The verification contract uses unmodified stock open62541 and open62541pp
sources and does not build third-party unit tests. Target Xenomai validation,
cross-distribution CI, and downstream application migration remain separate
gates.
