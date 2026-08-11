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
Xenomai-safe `StartStopManager` shutdown path after all cases complete.

**Tech Stack:** C++20, Orocos RTT/OCL, Xenomai 3.3.3, Boost.Test, CMake, CTest.

## Global Constraints

- Change only OCL's `deployment/tests/opcua_deployment_test.cpp` for the
  lifecycle correction.
- Do not change `OpcUaDeploymentComponent`, the production deployer, RTT, or
  `rtt_opcua` behavior.
- Preserve the existing OCL dependency-include edits in `bin/CMakeLists.txt`
  and `deployment/CMakeLists.txt`.
- Treat the bounded timeout of
  `explicit_start_publishes_only_deployer` as the required RED evidence.
- On Xenomai, do not call `__os_exit()` from the Boost.Test fixture; follow
  RTT's maintained test runner and stop/release `StartStopManager` instead.
- Commit only after the focused case, all six OPC UA deployment cases, and the
  complete OCL CTest suite pass.

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

- [ ] **Step 5: Run the complete OCL verification boundary**

```bash
cmake --build toolchain/tools/ocl/build --parallel 2
ctest --test-dir toolchain/tools/ocl/build --output-on-failure --timeout 120
git -C toolchain/tools/ocl diff --check
git -C toolchain/tools/ocl status --short
```

Expected: the full build exits `0`; all 13 OCL tests pass; `diff --check`
exits `0`; status contains only the two preserved CMake edits and the new test
harness edit.

- [ ] **Step 6: Commit the OCL changes on its default branch**

```bash
git -C toolchain/tools/ocl add -- \
  deployment/tests/opcua_deployment_test.cpp
git -C toolchain/tools/ocl commit -m \
  "test: initialize RTT in OPC UA deployment suite"
```

Expected: OCL `dev` contains one focused test-lifecycle commit. The two
pre-existing CMake edits remain unstaged for their separate dependency-header
commit during final integration. Generated build artifacts remain untracked or
ignored and are not committed.
