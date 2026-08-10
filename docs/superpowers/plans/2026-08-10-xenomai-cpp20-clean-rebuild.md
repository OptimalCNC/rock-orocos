# Xenomai C++20 Clean Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Synchronize the root and Autoproj-managed repositories, merge the existing RTT wakeup fix, and produce a clean validated C++20 Xenomai installation with `deployer-opcua-xenomai` at `/home/metanc/.orocos`.

**Architecture:** Preserve the local RTT patch before any source update, synchronize the workspace from the tracked Autoproj policy, and then reapply the patch on the updated RTT `dev` base. The lightweight bootstrap generates the workspace-local Autoproj launcher required by the one-time Stage 2 recovery without making Stage 2 part of normal `--skip-osdeps` operation. Delete only reviewed build/install artifacts and use the documented no-update maintainer flow so the final clean build cannot replace the intentional RTT working state.

**Tech Stack:** Git, Autoproj 2.18+, CMake 3.28, GCC 13/C++20, Orocos RTT/OCL, Xenomai 3.3.3, open62541 1.4.15, open62541pp 0.21.2, `rtt_opcua`, Boost.Test, Bash.

## Global Constraints

- Build target: `xenomai`.
- Xenomai prefix: `/usr/xenomai`; `xeno-config --version` must report `3.3.3`.
- Install prefix: `/home/metanc/.orocos`.
- Delete the old install prefix without retaining a backup.
- Require C++20 across maintained packages and generated oroGen projects.
- Build RTT with `ENABLE_MQ=ON` and `ENABLE_CORBA=OFF`.
- OPC UA may listen only on `127.0.0.1` and/or `::1`.
- Do not force-update, reset, clean, or delete source repositories.
- Do not push root or package branches.
- Preserve the RTT stash after reapplying it.
- Leave the merged RTT changes visible and uncommitted on `fix-execution-engine-nested-ownthread-wakeup`.
- Do not run another source update after reapplying the RTT patch.
- Keep `.autoproj`, package Git metadata, build logs, and unrelated files.
- `bootstrap.sh --skip-osdeps` must not install OS or Ruby dependencies.

---

### Task 1: Establish Recoverable Git State

**Files:**
- Preserve: `toolchain/tools/rtt/rtt/ExecutionEngine.cpp`
- Preserve: `toolchain/tools/rtt/tests/method_test.cpp`
- Preserve: `toolchain/tools/rtt/.git/refs/stash`
- Verify: `docs/superpowers/specs/2026-08-10-xenomai-cpp20-clean-rebuild-design.md`

**Interfaces:**
- Consumes: approved rebuild design and the current nested RTT working tree.
- Produces: a named RTT stash, a clean nested RTT checkout, and a root branch rebased on current `origin/main`.

- [ ] **Step 1: Verify the root branch and approved design commit**

Run:

```bash
git status --short --branch
git log -2 --oneline --decorate
git merge-base --is-ancestor origin/main HEAD
```

Expected: current branch is `codex/xenomai-cpp20-clean-rebuild`; the root is ahead of `origin/main` only by local design/plan documentation; the only pre-existing untracked root artifact is `CMakeFiles/`.

- [ ] **Step 2: Verify that RTT is the only checkout with tracked edits**

Run:

```bash
git -C toolchain/tools/rtt status --short --branch
git -C toolchain/tools/rtt diff --check
git -C toolchain/tools/rtt diff --stat
```

Then inspect every other existing checkout:

```bash
for repo_path in \
  toolchain/farbot \
  toolchain/rtlog-cpp \
  toolchain/tools/orogen \
  toolchain/tools/log4cpp \
  toolchain/tools/utilmm \
  toolchain/tools/rtt_typelib \
  toolchain/tools/ocl \
  toolchain/tools/typelib \
  toolchain/tools/utilrb \
  toolchain/stdint_typekit \
  tools/metaruby
do
  git -C "$repo_path" status --short --branch
done
```

Expected: RTT has modifications only in `rtt/ExecutionEngine.cpp` and `tests/method_test.cpp`; other checkouts have no tracked changes. Untracked package-local `build/` directories are allowed.

- [ ] **Step 3: Save the RTT patch in a named stash**

Run:

```bash
git -C toolchain/tools/rtt stash push \
  -m "pre-sync nested OwnThread wakeup 2026-08-10" \
  -- rtt/ExecutionEngine.cpp tests/method_test.cpp
git -C toolchain/tools/rtt stash list --format='%gd %H %s'
git -C toolchain/tools/rtt stash show --stat stash@{0}
git -C toolchain/tools/rtt checkout dev
git -C toolchain/tools/rtt status --short --branch
```

Expected: the newest stash contains exactly the two RTT files, the RTT tracked working tree is clean on `dev`, and the local feature branch remains available at its old base. Record the displayed full stash commit ID in the execution notes.

- [ ] **Step 4: Refresh root `origin/main` through HTTPS and rebase the maintenance branch**

Run:

```bash
git fetch https://github.com/liufang-robot/rock-orocos.git \
  +refs/heads/main:refs/remotes/origin/main
git rebase origin/main
git merge-base --is-ancestor origin/main HEAD
git status --short --branch
```

Expected: rebase succeeds without conflict and `origin/main` is an ancestor of `HEAD`. Do not delete `CMakeFiles/` yet.

### Task 2: Reconfigure Autoproj And Synchronize Sources

**Files:**
- Modify: `tools/common.sh`
- Modify: `tools/check-autoproj-policy.rb`
- Regenerate: `.autoproj/config.yml`
- Regenerate: `.autoproj/Gemfile`
- Regenerate: `.autoproj/bin/autoproj`
- Regenerate: `.autoproj/env.sh`
- Synchronize: package checkouts selected by `autoproj/manifest` and `autoproj/overrides.yml`

**Interfaces:**
- Consumes: updated root policy and a clean saved RTT working state from Task 1.
- Produces: a Stage-2-compatible workspace launcher and all selected source checkouts at the configured branches/tags, including new OPC UA dependencies.

- [ ] **Step 1: Confirm Xenomai discovery before reconfiguration**

Run:

```bash
/usr/xenomai/bin/xeno-config --version
/usr/xenomai/bin/xeno-config --skin=native --cflags
c++ --version
cmake --version
```

Expected: Xenomai reports `3.3.3`; compiler is GCC 13; CMake is 3.28.x.

- [ ] **Step 2: Ensure Autoproj is usable**

Run:

```bash
./tools/install-autoproj.sh
```

Expected: the command either reports an existing usable Autoproj or installs it successfully without editing shell startup files.

- [ ] **Step 3: Add a failing launcher policy test**

Add this assertion to `tools/check-autoproj-policy.rb` after the existing
`.autoproj/bin/bundle` assertion:

```ruby
unless common_script.include?('.autoproj/bin/autoproj') &&
       common_script.include?('ENV["AUTOPROJ_CURRENT_ROOT"]') &&
       common_script.include?('ENV["BUNDLE_GEMFILE"]') &&
       common_script.include?('Gem.clear_paths') &&
       common_script.include?('load Gem.bin_path("autoproj", "autoproj")')
  errors << "tools/common.sh: must seed a user-gem Autoproj launcher for Stage 2"
end
```

- [ ] **Step 4: Run the policy test and verify the intended failure**

Run:

```bash
ruby tools/check-autoproj-policy.rb
```

Expected: FAIL with `tools/common.sh: must seed a user-gem Autoproj launcher for Stage 2` because launcher generation is absent.

- [ ] **Step 5: Generate the workspace-local Autoproj launcher**

In `orocos_rock_prepare_autoproj_workspace`, after generating `bundle` and
`bundler`, add:

```bash
    autoproj_gem_path="$(orocos_rock_user_gem_path)"
    cat >"$OROCOS_ROCK_ROOT/.autoproj/bin/autoproj" <<EOF
#!$ruby_executable
require "rubygems"
ENV["AUTOPROJ_CURRENT_ROOT"] = "$OROCOS_ROCK_ROOT"
ENV["BUNDLE_GEMFILE"] ||= "$OROCOS_ROCK_ROOT/.autoproj/Gemfile"
ENV["GEM_PATH"] = "$autoproj_gem_path"
Gem.clear_paths
gem "facets", "< 3.2"
load Gem.bin_path("autoproj", "autoproj")
EOF
    chmod +x "$OROCOS_ROCK_ROOT/.autoproj/bin/autoproj"
```

The file must remain a Ruby program because Autoproj Stage 2 invokes it as
`ruby .autoproj/bin/autoproj`, bypassing its shebang.

- [ ] **Step 6: Verify the policy and shell tests pass**

Run:

```bash
ruby tools/check-autoproj-policy.rb
bash -n tools/common.sh tools/bootstrap.sh
```

Expected: both commands exit zero.

- [ ] **Step 7: Reconfigure the workspace for the final prefix and Xenomai target**

Run:

```bash
XENOMAI_DIR=/usr/xenomai \
XENOMAI_ROOT_DIR=/usr/xenomai \
PATH="/usr/xenomai/bin:$PATH" \
./tools/bootstrap.sh \
  --prefix /home/metanc/.orocos \
  --target xenomai \
  --skip-osdeps
```

Expected: `.autoproj/config.yml` contains the exact prefix, `rtt_target: xenomai`, `rtt_corba_implementation: none`, and `XENOMAI_DIR: /usr/xenomai`.

- [ ] **Step 8: Verify the generated launcher through the Stage 2 invocation boundary**

Run:

```bash
/usr/bin/ruby3.2 .autoproj/bin/autoproj --version
```

Expected: the command exits zero and reports Autoproj 2.18.x. This exact Ruby
invocation is required because it matches `Autoproj::Ops::Install#stage2`.

Record the selected source and retained-stash state immediately before Stage 2:

```bash
/bin/bash -lc '
set -euo pipefail
for repo_path in \
  toolchain/farbot \
  toolchain/rtlog-cpp \
  toolchain/tools/rtt \
  toolchain/open62541 \
  toolchain/open62541pp \
  toolchain/tools/rtt_opcua \
  toolchain/tools/ocl \
  toolchain/tools/orogen \
  toolchain/tools/typelib \
  toolchain/tools/utilmm \
  toolchain/tools/utilrb \
  toolchain/tools/rtt_typelib
do
  printf "%s\t" "$repo_path"
  git -C "$repo_path" rev-parse HEAD
  git -C "$repo_path" status --porcelain=v1 --untracked-files=no
done > /tmp/rock-orocos-stage2-sources.before
git -C toolchain/tools/rtt stash list --format="%H %s" \
  > /tmp/rock-orocos-stage2-stashes.before
'
```

Expected: both snapshot files are non-empty; no selected checkout reports a
tracked edit.

- [ ] **Step 9: Complete the one-time supported Stage 2 recovery**

Run:

```bash
/bin/bash -lc '
set -euo pipefail
export XENOMAI_DIR=/usr/xenomai
export XENOMAI_ROOT_DIR=/usr/xenomai
export PATH="/usr/xenomai/bin:$PATH"
export OROCOS_TARGET=xenomai
. tools/common.sh
orocos_rock_require_autoproj
orocos_rock_ensure_workspace_ruby_gems
orocos_rock_configure_target_environment xenomai
orocos_rock_autoproj install_stage2 "$OROCOS_ROCK_ROOT" --no-interactive
'
```

Expected: Stage 2 exits zero after generating the proper environment and
finishing its dependency phase. `.autoproj/env.sh` exists and a clean shell
can source root `env.sh` without diagnostics. Stop before cleanup or build if
Stage 2 fails.

- [ ] **Step 10: Verify Stage 2 preserved sources and the RTT stash**

Run:

```bash
/bin/bash -lc '
set -euo pipefail
for repo_path in \
  toolchain/farbot \
  toolchain/rtlog-cpp \
  toolchain/tools/rtt \
  toolchain/open62541 \
  toolchain/open62541pp \
  toolchain/tools/rtt_opcua \
  toolchain/tools/ocl \
  toolchain/tools/orogen \
  toolchain/tools/typelib \
  toolchain/tools/utilmm \
  toolchain/tools/utilrb \
  toolchain/tools/rtt_typelib
do
  printf "%s\t" "$repo_path"
  git -C "$repo_path" rev-parse HEAD
  git -C "$repo_path" status --porcelain=v1 --untracked-files=no
done > /tmp/rock-orocos-stage2-sources.after
git -C toolchain/tools/rtt stash list --format="%H %s" \
  > /tmp/rock-orocos-stage2-stashes.after
diff -u /tmp/rock-orocos-stage2-sources.before \
  /tmp/rock-orocos-stage2-sources.after
diff -u /tmp/rock-orocos-stage2-stashes.before \
  /tmp/rock-orocos-stage2-stashes.after
rm -f \
  /tmp/rock-orocos-stage2-sources.before \
  /tmp/rock-orocos-stage2-sources.after \
  /tmp/rock-orocos-stage2-stashes.before \
  /tmp/rock-orocos-stage2-stashes.after
'
```

Expected: both diffs are empty. The source refs, tracked worktrees, and full
RTT stash list are byte-for-byte unchanged by Stage 2.

- [ ] **Step 11: Update the exact selected source package set**

Run this as one shell so the helper functions and environment remain active:

```bash
/bin/bash -lc '
set -euo pipefail
export XENOMAI_DIR=/usr/xenomai
export XENOMAI_ROOT_DIR=/usr/xenomai
export PATH="/usr/xenomai/bin:$PATH"
export OROCOS_TARGET=xenomai
. tools/common.sh
orocos_rock_require_autoproj
orocos_rock_ensure_workspace_ruby_gems
orocos_rock_source_workspace_env
orocos_rock_configure_target_environment xenomai
orocos_rock_prepare_autoproj_workspace /home/metanc/.orocos none xenomai
orocos_rock_autoproj update \
  --no-interactive --no-osdeps --no-config --no-bundler --no-autoproj \
  farbot rtlog-cpp rtt open62541 open62541pp rtt_opcua \
  ocl orogen typelib utilmm rtt_typelib
'
```

Expected: Autoproj updates existing packages, creates `toolchain/open62541`, `toolchain/open62541pp`, and `toolchain/tools/rtt_opcua`, and reports no package update failure.

- [ ] **Step 12: Verify configured sources and C++20 content**

Run:

```bash
ruby tools/check-autoproj-policy.rb
ruby tools/check-cpp20-policy.rb
git -C toolchain/farbot branch --show-current
git -C toolchain/rtlog-cpp branch --show-current
git -C toolchain/tools/rtt rev-parse autobuild/dev
git -C toolchain/tools/ocl rev-parse autobuild/dev
git -C toolchain/tools/rtt_opcua rev-parse autobuild/dev
git -C toolchain/open62541 describe --tags --exact-match
git -C toolchain/open62541pp describe --tags --exact-match
```

Expected: policy checks pass; farbot selects `master`; rtlog-cpp selects `main`; maintained packages resolve their `dev` tracking refs; dependency tags are exactly `v1.4.15` and `v0.21.2`.

- [ ] **Step 13: Commit the reviewed bootstrap repair**

Run:

```bash
git add tools/common.sh tools/check-autoproj-policy.rb
git commit -m "fix: generate Autoproj workspace launcher"
```

Expected: the commit contains only the launcher implementation and its policy
regression. Generated `.autoproj` state, source refs, and build artifacts are
not committed.

### Task 3: Rebase And Reapply The RTT Wakeup Fix

**Files:**
- Modify: `toolchain/tools/rtt/rtt/ExecutionEngine.cpp`
- Modify: `toolchain/tools/rtt/tests/method_test.cpp`

**Interfaces:**
- Consumes: updated RTT `autobuild/dev` and the named stash from Task 1.
- Produces: the local feature branch based on current RTT `dev`, with the wakeup fix and regression visible in the working tree.

- [ ] **Step 1: Move the feature branch to the updated RTT base**

Run:

```bash
git -C toolchain/tools/rtt checkout fix-execution-engine-nested-ownthread-wakeup
git -C toolchain/tools/rtt branch -f dev autobuild/dev
git -C toolchain/tools/rtt rebase dev
git -C toolchain/tools/rtt merge-base --is-ancestor dev HEAD
```

Expected: the feature branch points at the updated `dev` history before local changes are reapplied.

- [ ] **Step 2: Apply the saved stash without dropping it**

Locate and apply the saved full commit ID in one shell:

```bash
/bin/bash -lc '
set -euo pipefail
rtt_repo=toolchain/tools/rtt
rtt_stash_oid="$(
  git -C "$rtt_repo" stash list --format="%H %s" |
    awk '\''/pre-sync nested OwnThread wakeup 2026-08-10/ { print $1; exit }'\''
)"
test -n "$rtt_stash_oid"
printf "Applying retained RTT stash %s\n" "$rtt_stash_oid"
git -C "$rtt_repo" stash apply "$rtt_stash_oid"
git -C "$rtt_repo" status --short
'
```

Expected: either both files apply cleanly or Git reports conflicts only in the two approved RTT files. The stash remains listed.

- [ ] **Step 3: Resolve any semantic overlap with updated RTT**

The desired wakeup behavior in `ExecutionEngine.cpp` is exactly:

```cpp
{
    MutexLock lock(msg_lock);
    msg_cond.broadcast(); // required for waitAndProcessMessages() (EE thread)
}
```

If updated `dev` already locks `msg_lock` around this broadcast, retain the updated implementation and omit the duplicate hunk. The regression in `method_test.cpp` must include `internal/GlobalEngine.hpp` and retain this behavior:

```cpp
BOOST_AUTO_TEST_CASE(testNestedOwnThreadOperationCallerCall)
{
    OperationCaller<double(void)> nested(
        caller->provides()->getOperation("o0"),
        RTT::internal::GlobalEngine::Instance());

    BOOST_REQUIRE(nested.ready());
    BOOST_CHECK_EQUAL(-1.0, nested());
}
```

Use `apply_patch` for manual conflict resolution. Remove conflict markers and keep updated C++20 API spellings from `dev`.

- [ ] **Step 4: Verify the merged working state and recovery copy**

Run:

```bash
git -C toolchain/tools/rtt diff --check
git -C toolchain/tools/rtt diff --name-only
git -C toolchain/tools/rtt diff --stat
git -C toolchain/tools/rtt stash list --format='%gd %H %s'
git -C toolchain/tools/rtt status --short --branch
```

Expected: only the two approved files are modified, no conflict markers or whitespace errors remain, and the named stash is still present. Do not commit these user-owned changes.

### Task 4: Run Policy Gates And Remove Old Artifacts

**Files:**
- Delete: `/home/metanc/liufang/src/rock-orocos/CMakeFiles/`
- Delete: reviewed package-local `build/` directories under `toolchain/`
- Delete: `/home/metanc/.orocos/`
- Preserve: all package source directories and `.autoproj/`

**Interfaces:**
- Consumes: synchronized sources and the merged RTT working state.
- Produces: a source-complete workspace with no prior package build trees or installed prefix.

- [ ] **Step 1: Run all pre-clean policy and syntax gates**

Run:

```bash
ruby tools/check-repository-policy.rb
ruby tools/check-autoproj-policy.rb
ruby tools/check-cpp20-policy.rb
bash -n tools/common.sh tools/bootstrap.sh tools/install.sh
bash -n tools/export-env.sh tools/validate-install.sh tools/setup.sh
```

Expected: every command exits zero.

- [ ] **Step 2: Inventory the exact deletion targets and disk usage**

Run:

```bash
find toolchain -type d -name build -prune -print
du -sh /home/metanc/.orocos toolchain
df -h /home/metanc/liufang/src/rock-orocos /home/metanc/.orocos
```

Expected build roots are limited to package directories for farbot, rtlog-cpp, RTT, OCL, Typelib, utilmm, rtt_typelib, open62541, open62541pp, rtt_opcua, and obsolete log4cpp/stdint_typekit. Stop if a listed path is outside a package root.

- [ ] **Step 3: Delete only the approved generated artifacts**

Run the following with the filesystem approval needed for `/home/metanc/.orocos`:

```bash
rm -rf \
  /home/metanc/liufang/src/rock-orocos/CMakeFiles \
  /home/metanc/liufang/src/rock-orocos/toolchain/farbot/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/rtlog-cpp/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/open62541/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/open62541pp/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/tools/rtt/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/tools/rtt_opcua/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/tools/orogen/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/tools/typelib/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/tools/utilmm/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/tools/rtt_typelib/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/tools/log4cpp/build \
  /home/metanc/liufang/src/rock-orocos/toolchain/stdint_typekit/build \
  /home/metanc/.orocos
```

Expected: only generated build/install artifacts are removed. The user explicitly approved removal without a backup.

- [ ] **Step 4: Verify the clean boundary and recovered space**

Run:

```bash
test ! -e /home/metanc/.orocos
test ! -e CMakeFiles
find toolchain -type d -name build -prune -print
git -C toolchain/tools/rtt status --short --branch
df -h /home/metanc/liufang/src/rock-orocos
```

Expected: no reviewed package build directory remains; RTT still modifies only the approved file set; free space has increased. Do not remove an unexpected remaining build directory until its package ownership is established.

### Task 5: Build And Install Without Updating Sources

**Files:**
- Generate: package-local `build/` directories under `toolchain/`
- Generate: `/home/metanc/.orocos/toolchain/`
- Generate: `/home/metanc/.orocos/env.sh`
- Generate: `/home/metanc/.orocos/dev-env.sh`

**Interfaces:**
- Consumes: clean source trees, Xenomai 3.3.3, and the merged RTT patch.
- Produces: the complete installed C++20 Xenomai prefix.

- [ ] **Step 1: Resolve source-declared OS dependencies**

Run:

```bash
/bin/bash -lc '
set -euo pipefail
export XENOMAI_DIR=/usr/xenomai
export XENOMAI_ROOT_DIR=/usr/xenomai
export PATH="/usr/xenomai/bin:$PATH"
export OROCOS_TARGET=xenomai
. tools/common.sh
orocos_rock_require_autoproj
orocos_rock_ensure_workspace_ruby_gems
orocos_rock_source_workspace_env
orocos_rock_configure_target_environment xenomai
orocos_rock_prepare_autoproj_workspace /home/metanc/.orocos none xenomai
orocos_rock_autoproj osdeps --no-interactive
'
```

Expected: required operating-system dependencies are already present or are installed successfully. This step may request `sudo`; it must not update source checkouts.

- [ ] **Step 2: Build the selected Autoproj layout from clean build trees**

Run:

```bash
/bin/bash -lc '
set -euo pipefail
export XENOMAI_DIR=/usr/xenomai
export XENOMAI_ROOT_DIR=/usr/xenomai
export PATH="/usr/xenomai/bin:$PATH"
export OROCOS_TARGET=xenomai
. tools/common.sh
orocos_rock_require_autoproj
orocos_rock_ensure_workspace_ruby_gems
orocos_rock_source_workspace_env
orocos_rock_configure_target_environment xenomai
orocos_rock_prepare_autoproj_workspace /home/metanc/.orocos none xenomai
orocos_rock_autoproj build --no-interactive
'
```

Expected: all selected packages configure, compile, and install with C++20, Xenomai, mqueue enabled, CORBA disabled, and no source update. Preserve the first failing package log if the command fails.

- [ ] **Step 3: Stage Ruby generator tools and export the environments**

Run:

```bash
./tools/install-ruby-tools.sh --prefix /home/metanc/.orocos
XENOMAI_DIR=/usr/xenomai \
XENOMAI_ROOT_DIR=/usr/xenomai \
./tools/export-env.sh --prefix /home/metanc/.orocos --target xenomai
```

Expected: `env.sh` and `dev-env.sh` exist and reference `/home/metanc/.orocos`; installed `orogen` and `typegen` are under the prefix.

- [ ] **Step 4: Run the installed-prefix contract validator**

Run:

```bash
XENOMAI_DIR=/usr/xenomai \
XENOMAI_ROOT_DIR=/usr/xenomai \
./tools/validate-install.sh \
  --prefix /home/metanc/.orocos \
  --target xenomai
```

Expected: validation reports `Validated Orocos/Rock xenomai install prefix: /home/metanc/.orocos` and confirms the deployers, browser, mqueue library, OPC UA metadata, `orogen`, and `typegen`.

### Task 6: Run The Focused RTT Regression

**Files:**
- Reconfigure: `toolchain/tools/rtt/build/`
- Test: `toolchain/tools/rtt/tests/method_test.cpp`

**Interfaces:**
- Consumes: installed Xenomai prefix and merged RTT source.
- Produces: executable evidence that the nested OwnThread call completes without a lost wakeup.

- [ ] **Step 1: Enable RTT tests in the clean Xenomai build tree**

Run:

```bash
/bin/bash -lc '
set -euo pipefail
. /home/metanc/.orocos/dev-env.sh
export XENOMAI_DIR=/usr/xenomai
export XENOMAI_ROOT_DIR=/usr/xenomai
export PATH="/usr/xenomai/bin:$PATH"
export OROCOS_TARGET=xenomai
cmake -S toolchain/tools/rtt -B toolchain/tools/rtt/build \
  -DENABLE_TESTS=ON \
  -DBUILD_TESTING=ON \
  -DENABLE_MQ=ON \
  -DENABLE_CORBA=OFF
cmake --build toolchain/tools/rtt/build --parallel 2 --target method_test
'
```

Expected: `toolchain/tools/rtt/build/tests/method_test` builds successfully against the installed C++20/Xenomai dependencies.

- [ ] **Step 2: Run only the new regression with a hang bound**

Run:

```bash
/bin/bash -lc '
set -euo pipefail
. /home/metanc/.orocos/env.sh
timeout 30s toolchain/tools/rtt/build/tests/method_test \
  --run_test=OperationCallerTestSuite/testNestedOwnThreadOperationCallerCall \
  --log_level=test_suite
'
```

Expected: one Boost.Test case runs and passes before the 30-second timeout.

- [ ] **Step 3: Run the complete method test executable through CTest**

Run:

```bash
ctest --test-dir toolchain/tools/rtt/build \
  --output-on-failure \
  --timeout 120 \
  -R '^method_test$'
```

Expected: `method_test` passes.

### Task 7: Prove The OPC UA Xenomai Listener Is Loopback-Only

**Files:**
- Create temporarily: `/tmp/rock-orocos-opcua-xenomai-smoke.ops`
- Generate: `/tmp/rock-orocos-opcua-xenomai-smoke.log`

**Interfaces:**
- Consumes: installed `deployer-opcua-xenomai` and Xenomai runtime environment.
- Produces: bounded startup and socket-listener evidence for `opc.tcp://127.0.0.1:4840/rtt`.

- [ ] **Step 1: Create the minimal startup script using `apply_patch`**

Apply this patch:

```diff
*** Begin Patch
*** Add File: /tmp/rock-orocos-opcua-xenomai-smoke.ops
+opcua.start()
*** End Patch
```

Expected: the script starts the built-in Deployer publication without application-specific typekits or components.

- [ ] **Step 2: Launch, inspect, and terminate the deployer in one bounded shell**

Run:

```bash
/bin/bash -lc '
set -euo pipefail
. /home/metanc/.orocos/env.sh
smoke_log=/tmp/rock-orocos-opcua-xenomai-smoke.log
deployer-opcua-xenomai \
  -s /tmp/rock-orocos-opcua-xenomai-smoke.ops -- \
  >"$smoke_log" 2>&1 &
smoke_pid=$!

cleanup_smoke() {
    smoke_forced=0
    if kill -0 "$smoke_pid" 2>/dev/null; then
        kill -TERM "$smoke_pid"
        for unused_attempt in $(seq 1 20); do
            kill -0 "$smoke_pid" 2>/dev/null || break
            sleep 0.1
        done
    fi
    if kill -0 "$smoke_pid" 2>/dev/null; then
        smoke_forced=1
        kill -KILL "$smoke_pid"
    fi
    wait "$smoke_pid" 2>/dev/null || true
}
trap cleanup_smoke EXIT

listener_found=0
for unused_attempt in $(seq 1 50); do
    kill -0 "$smoke_pid"
    listener_output="$(ss -ltn "sport = :4840")"
    if rg -q "127\\.0\\.0\\.1:4840|\\[::1\\]:4840" <<<"$listener_output"; then
        listener_found=1
        break
    fi
    sleep 0.2
done

test "$listener_found" -eq 1
kill -0 "$smoke_pid"
listener_output="$(ss -ltn "sport = :4840")"
printf "%s\n" "$listener_output"
! rg -q "0\\.0\\.0\\.0:4840|\\*:4840|\\[::\\]:4840" <<<"$listener_output"
cleanup_smoke
trap - EXIT
test "$smoke_forced" -eq 0
'
```

Expected: the process remains alive, port 4840 is listening on `127.0.0.1` and/or `::1`, no wildcard address is present, and the process exits after `SIGTERM` without requiring `SIGKILL`. Inspect the smoke log if any assertion fails.

- [ ] **Step 3: Verify installed OPC UA command identity**

Run:

```bash
/bin/bash -lc '
set -euo pipefail
. /home/metanc/.orocos/env.sh
command -v deployer-opcua-xenomai
command -v ctaskbrowser-opcua-xenomai
deployer-opcua-xenomai --version
ctaskbrowser-opcua-xenomai --version
pkg-config --modversion rtt_opcua-xenomai
pkg-config --modversion ocl-deployment-xenomai
'
```

Expected: every path resolves inside `/home/metanc/.orocos`, both executables report versions successfully, and both pkg-config packages resolve.

### Task 8: Final State Audit

**Files:**
- Verify: `/home/metanc/.orocos/env.sh`
- Verify: `/home/metanc/.orocos/dev-env.sh`
- Verify: nested repository and stash state

**Interfaces:**
- Consumes: all synchronization, build, and runtime evidence.
- Produces: a concise handoff containing exact installed target, repository state, validation results, and residual risks.

- [ ] **Step 1: Verify the installed public contract one final time**

Run:

```bash
/bin/bash -lc '
set -euo pipefail
. /home/metanc/.orocos/dev-env.sh
test "$OROCOS_PREFIX" = /home/metanc/.orocos
test "$OROCOS_TARGET" = xenomai
command -v deployer-xenomai
command -v deployer-opcua-xenomai
command -v ctaskbrowser-opcua-xenomai
command -v orogen
command -v typegen
test -f /home/metanc/.orocos/toolchain/lib/orocos/xenomai/types/librtt-transport-mqueue-xenomai.so
'
```

Expected: every assertion succeeds and every command resolves from the fresh prefix.

- [ ] **Step 2: Audit root and RTT Git state**

Run:

```bash
git status --short --branch
git log -3 --oneline --decorate
git -C toolchain/tools/rtt status --short --branch
git -C toolchain/tools/rtt diff --check
git -C toolchain/tools/rtt diff --name-only
git -C toolchain/tools/rtt stash list --format='%gd %H %s'
```

Expected: root contains only committed design/plan documentation beyond `origin/main`; RTT is based on updated `dev`, modifies one or both approved files plus generated build artifacts, has no other tracked edits, and retains the named recovery stash.

- [ ] **Step 3: Record selected package revisions and disk state**

Run:

```bash
for repo_path in \
  toolchain/farbot \
  toolchain/rtlog-cpp \
  toolchain/tools/rtt \
  toolchain/open62541 \
  toolchain/open62541pp \
  toolchain/tools/rtt_opcua \
  toolchain/tools/ocl \
  toolchain/tools/orogen \
  toolchain/tools/typelib \
  toolchain/tools/utilmm \
  toolchain/tools/utilrb \
  toolchain/tools/rtt_typelib \
  tools/metaruby
do
  printf '%s\t' "$repo_path"
  git -C "$repo_path" rev-parse HEAD
done
git -C toolchain/open62541 describe --tags --exact-match
git -C toolchain/open62541pp describe --tags --exact-match
du -sh /home/metanc/.orocos toolchain
df -h /home/metanc/liufang/src/rock-orocos
```

Expected: open62541 is `v1.4.15`, open62541pp is `v0.21.2`, and revision output is available for the final report.

- [ ] **Step 4: Report completion evidence**

The final handoff must state:

```text
Root branch and commit
Selected Xenomai version and target
Fresh prefix path
Install validation result
Focused RTT regression result
OPC UA loopback listener result
RTT modified-file list and retained stash ID
Any build warnings, skipped checks, or residual runtime limitations
```

Do not claim completion unless all required commands above have fresh passing output.
