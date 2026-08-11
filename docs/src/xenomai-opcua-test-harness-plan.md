# Xenomai OPC UA Test Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the maintained OCL OPC UA deployment tests initialize and shut
down RTT correctly when they run against the Xenomai target.

**Architecture:** Add one Boost.Test process fixture to the existing OCL OPC UA
deployment test executable. The fixture follows RTT's own test runner: it calls
`__os_init()` once with Boost.Test's real process arguments and uses RTT's
Xenomai-safe `StartStopManager` shutdown path after all cases complete. Keep
the production TaskBrowser CLI unchanged; its CTest definitions avoid
Xenomai-owned help flags and retain parser coverage through application-owned
validation failures.

**Tech Stack:** C++20, Orocos RTT/OCL, Xenomai 3.3.3, Boost.Test, CMake, CTest.

## Global Constraints

- Change only OCL's `deployment/tests/opcua_deployment_test.cpp` for the
  lifecycle correction and `bin/CMakeLists.txt` for the target-aware CLI test
  correction.
- Do not change `OpcUaDeploymentComponent`, the production deployer, RTT, or
  `rtt_opcua` behavior. Do not change `ctaskbrowser-opcua.cpp` or its installed
  wrapper.
- Preserve the existing OCL dependency-include edits in `bin/CMakeLists.txt`
  and `deployment/CMakeLists.txt`.
- Treat the bounded timeout of
  `explicit_start_publishes_only_deployer` as the required RED evidence.
- On Xenomai, do not call `__os_exit()` from the Boost.Test fixture; follow
  RTT's maintained test runner and stop/release `StartStopManager` instead.
- On Xenomai, do not register an assertion for application-specific `--help`;
  Xenomai owns that process-level option before `ORO_main` runs.
- Commit only after the focused case, all six OPC UA deployment cases, and the
  complete 12-test Xenomai OCL CTest suite pass.

---

### Task 1: Initialize RTT Around The OCL OPC UA Test Process

**Files:**

- Modify: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`
- Test: `toolchain/tools/ocl/deployment/tests/opcua_deployment_test.cpp`

**Interfaces:**

- Consumes: `int __os_init(int argc, char **argv)`,
  `void __os_exit()`, `RTT::os::StartStopManager`, and
  `boost::unit_test::framework::master_test_suite()`.
- Produces: one process-scoped `RttProcessFixture` registered with
  `BOOST_GLOBAL_FIXTURE`; no production interface changes.

- [ ] **Step 1: Reconfirm the existing focused RED result**

Run from the repository root:

```bash
timeout --signal=TERM --kill-after=5s 20s \
  toolchain/tools/ocl/build/deployment/ocl_opcua_deployment_test \
  --run_test=explicit_start_publishes_only_deployer \
  --log_level=test_suite
```

Expected: exit `124`; the test enters
`explicit_start_publishes_only_deployer` and blocks while constructing the
first RTT `TaskContext`. This is the behavior already reproduced before the
plan was written.

- [ ] **Step 2: Add the minimal process fixture**

Add these RTT lifecycle headers with the existing RTT includes:

```cpp
#include <rtt/os/StartStopManager.hpp>
#include <rtt/os/startstop.h>
```

Add this fixture inside the existing anonymous namespace, after the standard
library includes and before helper types:

```cpp
class RttProcessFixture final {
public:
  RttProcessFixture() {
    auto &suite = boost::unit_test::framework::master_test_suite();
    if (__os_init(suite.argc, suite.argv) != 0) {
      throw std::runtime_error("failed to initialize RTT test process");
    }
  }

  ~RttProcessFixture() {
#ifdef OROCOS_TARGET_XENOMAI
    RTT::os::StartStopManager::Instance()->stop();
    RTT::os::StartStopManager::Release();
#else
    __os_exit();
#endif
  }

  RttProcessFixture(const RttProcessFixture &) = delete;
  RttProcessFixture &operator=(const RttProcessFixture &) = delete;
};

BOOST_GLOBAL_FIXTURE(RttProcessFixture);
```

Do not move initialization into individual cases. The RTT registries and main
thread are process-global, so their lifecycle must also be process-global.

- [ ] **Step 3: Build and prove the focused case is GREEN**

```bash
cmake --build toolchain/tools/ocl/build --parallel 2 \
  --target ocl_opcua_deployment_test
timeout --signal=TERM --kill-after=5s 20s \
  toolchain/tools/ocl/build/deployment/ocl_opcua_deployment_test \
  --run_test=explicit_start_publishes_only_deployer \
  --log_level=test_suite
```

Expected: the build and test exit `0`; Boost.Test reports `No errors detected`
without reaching the timeout.

- [ ] **Step 4: Run every OPC UA deployment case**

```bash
ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
  --timeout 120 -R '^ocl_opcua_deployment_.*$'
```

Expected: all six selected tests pass and no test times out.

- [ ] **Step 5: Verify the fixture boundary and preserved changes**

```bash
cmake --build toolchain/tools/ocl/build --parallel 2
git -C toolchain/tools/ocl diff --check
git -C toolchain/tools/ocl status --short
```

Expected: the full build and `diff --check` exit `0`; status contains only the
two preserved CMake edits and the new test harness edit.

---

### Task 2: Keep TaskBrowser CLI Tests Target-Aware

**Files:**

- Modify: `toolchain/tools/ocl/bin/CMakeLists.txt`
- Test: CTest registrations generated from
  `toolchain/tools/ocl/bin/CMakeLists.txt`

**Interfaces:**

- Consumes: CMake cache variable `OROCOS_TARGET`, the existing
  `ctaskbrowser-opcua` executable, and its existing command-line parser.
- Produces: a non-Xenomai application-help test plus target-independent
  empty-import and repeated-import parser tests that do not use `--help` as a
  short-circuit.

- [ ] **Step 1: Preserve the observed Xenomai RED evidence**

The pre-change complete suite has already produced this required result:

```text
ctaskbrowser_opcua_help: failed because Xenomai printed its own help
ctaskbrowser_opcua_empty_import: failed because Xenomai consumed --help
ctaskbrowser_opcua_repeated_imports: failed because Xenomai consumed --help
```

The full command exited `8` with 3 failures out of 13. Do not add a standalone
`--` parser or change production code to satisfy these tests.

- [ ] **Step 2: Make only the CTest definitions target-aware**

Wrap the help-output test in this target condition:

```cmake
IF(NOT "${OROCOS_TARGET}" STREQUAL "xenomai")
  add_test(NAME ctaskbrowser_opcua_help
    COMMAND $<TARGET_FILE:ctaskbrowser-opcua> --help)
  set_tests_properties(ctaskbrowser_opcua_help PROPERTIES
    PASS_REGULAR_EXPRESSION "--import PACKAGE")
ENDIF()
```

Replace the empty-import test with an application-owned failure:

```cmake
add_test(NAME ctaskbrowser_opcua_empty_import
  COMMAND $<TARGET_FILE:ctaskbrowser-opcua> --import=)
set_tests_properties(ctaskbrowser_opcua_empty_import PROPERTIES
  PASS_REGULAR_EXPRESSION "--import requires a package name")
```

Replace the repeated-import help short-circuit with an arity failure that is
reached only after both import forms parse successfully:

```cmake
add_test(NAME ctaskbrowser_opcua_repeated_imports
  COMMAND $<TARGET_FILE:ctaskbrowser-opcua>
    --import fixture_a --import=fixture_b)
set_tests_properties(ctaskbrowser_opcua_repeated_imports PROPERTIES
  PASS_REGULAR_EXPRESSION
    "exactly one endpoint and one component name are required")
```

`PASS_REGULAR_EXPRESSION` intentionally owns the result of these two negative
tests: CTest ignores the process exit code and passes only when the required
application diagnostic appears. Do not combine it with `WILL_FAIL`, which
would invert the regex-confirmed success.

- [ ] **Step 3: Regenerate and verify the CLI registrations**

```bash
cmake --build toolchain/tools/ocl/build --parallel 2 \
  --target ctaskbrowser-opcua
ctest --test-dir toolchain/tools/ocl/build -N -V \
  -R '^ctaskbrowser_opcua_.*$'
ctest --test-dir toolchain/tools/ocl/build --output-on-failure \
  --timeout 30 -R '^ctaskbrowser_opcua_.*$'
```

Expected on Xenomai: four tests are registered because the help-output test is
omitted; all four pass; empty and repeated import cases emit their exact
application diagnostics rather than Xenomai help.

- [ ] **Step 4: Run the complete OCL verification boundary**

```bash
cmake --build toolchain/tools/ocl/build --parallel 2
ctest --test-dir toolchain/tools/ocl/build --output-on-failure --timeout 120
git -C toolchain/tools/ocl diff --check
git -C toolchain/tools/ocl status --short
```

Expected: the full build exits `0`; all 12 Xenomai OCL tests pass;
`diff --check` exits `0`; status contains only the two approved CMake files and
the new test harness edit.

- [ ] **Step 5: Commit the verified OCL changes on its default branch**

```bash
git -C toolchain/tools/ocl add -- \
  bin/CMakeLists.txt deployment/CMakeLists.txt \
  deployment/tests/opcua_deployment_test.cpp
git -C toolchain/tools/ocl commit -m \
  "build: harden Xenomai OPC UA integration"
```

Expected: OCL `dev` contains one verified C++20/Xenomai OPC UA integration
commit and its tracked working tree is clean. Generated build artifacts remain
untracked or ignored and are not committed.
