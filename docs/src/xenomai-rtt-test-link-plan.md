# Xenomai RTT Test Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make RTT's complete configured test set link and run against the
selected Xenomai target while preserving the reviewed ExecutionEngine wakeup
fix.

**Architecture:** Remove the redundant GNU/Linux-only typekit link from
`typekit_test`. The shared RTT `TEST_LIBRARIES` list already supplies
`rtt-typekit-${OROCOS_TARGET}_plugin`, so the test continues to link one
target-selected typekit without adding a new dependency or runtime behavior.

**Tech Stack:** C++20, CMake, CTest, Orocos RTT 2.10, Xenomai 3.3.3,
Boost.Test.

## Global Constraints

- Change only `toolchain/tools/rtt/tests/CMakeLists.txt` for the test-link
  correction.
- Preserve the reviewed changes in `rtt/ExecutionEngine.cpp` and
  `tests/method_test.cpp` exactly.
- Preserve both RTT stashes; do not pop, drop, rewrite, or clear them.
- Do not add another typekit library. The existing target-selected dependency
  in `TEST_LIBRARIES` is authoritative.
- Treat the full-build linker failure for
  `-lrtt-typekit-gnulinux_plugin` as the required RED evidence.
- Require `-std=c++20`, a complete RTT build, all 42 configured RTT tests, and
  the focused `method_test` regression before committing.
- Keep the test-link correction and ExecutionEngine behavior change as two
  focused commits, then fast-forward RTT's default `dev` branch.

---

### Task 1: Remove The Cross-Target RTT Test Link

**Files:**

- Modify: `toolchain/tools/rtt/tests/CMakeLists.txt`
- Test: `toolchain/tools/rtt/tests/typekit_test.cpp`

**Interfaces:**

- Consumes: `TEST_LIBRARIES`, which contains
  `rtt-typekit-${OROCOS_TARGET}_plugin`.
- Produces: `typekit_test` linked only through the existing target-selected
  dependency; no new CMake target or runtime interface.

- [ ] **Step 1: Preserve the observed RED evidence**

The complete pre-change build has already failed with:

```text
/usr/bin/ld: cannot find -lrtt-typekit-gnulinux_plugin
gmake[2]: *** [tests/CMakeFiles/typekit_test.dir/build.make:123:
  tests/typekit_test] Error 1
```

The generated link command contains both the correct
`librtt-typekit-xenomai.so.2.10.0` from `TEST_LIBRARIES` and the redundant
hardcoded `-lrtt-typekit-gnulinux_plugin` from `tests/CMakeLists.txt`.

- [ ] **Step 2: Remove only the redundant link item**

Delete this line from `tests/CMakeLists.txt`:

```cmake
target_link_libraries(typekit_test rtt-typekit-gnulinux_plugin)
```

Keep the adjacent `ADD_UNIT_TEST` and `target_include_directories` calls
unchanged. Do not replace the line with another target-specific link because
`TEST_LIBRARIES` already supplies it.

- [ ] **Step 3: Build the complete configured RTT target set**

```bash
cmake --build toolchain/tools/rtt/build --parallel 2
```

Expected: exit `0`; `typekit_test` and every other configured RTT test
executable link successfully.

- [ ] **Step 4: Run all configured RTT tests**

```bash
ctest --test-dir toolchain/tools/rtt/build --output-on-failure --timeout 120
```

Expected: all 42 tests run; no test is missing, failed, or timed out.

- [ ] **Step 5: Reconfirm the focused wakeup regression and C++20**

```bash
ctest --test-dir toolchain/tools/rtt/build --output-on-failure \
  --timeout 30 -R '^method_test$'
rg -n -- '-std=(gnu\+\+|c\+\+)20' \
  toolchain/tools/rtt/build/compile_commands.json
git -C toolchain/tools/rtt diff --check
```

Expected: `method_test` passes; compile commands contain `-std=c++20`;
`diff --check` exits `0`.

- [ ] **Step 6: Commit the target-correct test link**

```bash
git -C toolchain/tools/rtt add -- tests/CMakeLists.txt
git -C toolchain/tools/rtt commit -m \
  "test: link RTT typekit for the configured target"
```

Expected: the commit contains only removal of the redundant hardcoded link.

- [ ] **Step 7: Commit the reviewed wakeup protocol**

```bash
git -C toolchain/tools/rtt add -- \
  rtt/ExecutionEngine.cpp tests/method_test.cpp
git -C toolchain/tools/rtt commit -m \
  "fix: prevent ExecutionEngine lost wakeups"
```

Expected: the commit contains only the under-lock notification/queue check and
its deterministic regression test.

- [ ] **Step 8: Fast-forward the default branch without touching stashes**

```bash
git -C toolchain/tools/rtt switch dev
git -C toolchain/tools/rtt merge --ff-only \
  fix-execution-engine-nested-ownthread-wakeup
git -C toolchain/tools/rtt stash list
git -C toolchain/tools/rtt status --short --branch
```

Expected: `dev` points to both new commits, its tracked working tree is clean,
and both pre-existing stash entries remain present.
