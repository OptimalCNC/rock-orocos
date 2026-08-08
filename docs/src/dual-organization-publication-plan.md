# Dual-Organization Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish every maintained Orocos/Rock default branch to
`liufang-robot`, synchronize it safely to `OptimalCNC`, and make the
OptimalCNC root workspace select only OptimalCNC-maintained forks.

**Architecture:** Package repositories publish identical commits to both
organizations. The root repository has a canonical `liufang-robot/main`
lineage and an OptimalCNC distribution lineage containing one additional
organization-policy commit. Every remote update is fast-forward-only and is
verified by its remote commit ID.

**Tech Stack:** Git, GitHub CLI, Autoproj policy YAML, Ruby policy checks,
Bash, CMake/CTest.

## Global Constraints

- Publish only `main`, `master`, or `dev` branches listed in the approved
  repository matrix.
- Do not create remote feature branches.
- Do not force-push, delete remote commits, tags, repositories, or branches.
- Keep `open62541`, `open62541pp`, and `utilrb` on their official upstreams.
- Create missing OptimalCNC repositories as public repositories.
- Leave Autoproj's `autobuild` remotes under Autoproj control.
- Keep `.tb_history` and generated `build/` directories untracked.
- Stop on a failed test, rejected push, permission error, unexpected remote
  commit, or non-fast-forward relationship.
- Do not commit files below `docs/superpowers/`.

---

### Task 1: Verify all publication inputs

**Files:**
- Inspect: `autoproj/overrides.yml`
- Inspect: `tools/check-autoproj-policy.rb`
- Inspect: each maintained package default branch

**Interfaces:**
- Consumes: the approved matrix in
  `docs/src/dual-organization-publication.md`.
- Produces: clean, tested local default branches suitable for publication.

- [ ] **Step 1: Capture the exact repository matrix**

Use these repository paths and branches:

```text
.                                  main
toolchain/farbot                   master
toolchain/rtlog-cpp                main
toolchain/tools/rtt                dev
toolchain/tools/rtt_opcua          dev
toolchain/tools/ocl                dev
toolchain/tools/orogen             dev
toolchain/tools/typelib            dev
toolchain/tools/utilmm             dev
toolchain/tools/rtt_typelib        dev
```

For each path, run:

```bash
git -C "$repository" status --short --branch
git -C "$repository" log -1 --oneline --decorate
```

Expected: only generated `build/` directories and the root `.tb_history` may
be untracked. No tracked file may be modified.

- [ ] **Step 2: Run root policy validation**

Run from the root repository:

```bash
ruby tools/check-repository-policy.rb
ruby tools/check-autoproj-policy.rb
ruby tools/check-clean-room-docker.rb
ruby tools/check-native-ci.rb
ruby tools/check-package-tests-ci.rb
ruby tools/check-cpp20-policy.rb
bash -n tools/common.sh tools/bootstrap.sh tools/install.sh
bash -n tools/export-env.sh tools/validate-install.sh tools/setup.sh
git diff --check
```

Expected: every command exits zero.

- [ ] **Step 3: Run the maintained package test matrix**

Build and validate a fresh GNU/Linux prefix below `/tmp`:

```bash
test ! -e /tmp/orocos-dual-publication-20260808
mkdir -p /tmp/orocos-dual-publication-20260808
./tools/setup.sh \
  --prefix /tmp/orocos-dual-publication-20260808/prefix \
  --target gnulinux
```

Then run the maintained package matrix against that prefix:

```bash
./tools/test-package.sh --prefix /tmp/orocos-dual-publication-20260808/prefix --target gnulinux utilmm
./tools/test-package.sh --prefix /tmp/orocos-dual-publication-20260808/prefix --target gnulinux typelib-cxx
./tools/test-package.sh --prefix /tmp/orocos-dual-publication-20260808/prefix --target gnulinux rtt-typelib
./tools/test-package.sh --prefix /tmp/orocos-dual-publication-20260808/prefix --target gnulinux rtt-core
./tools/test-package.sh --prefix /tmp/orocos-dual-publication-20260808/prefix --target gnulinux rtt-opcua
./tools/test-package.sh --prefix /tmp/orocos-dual-publication-20260808/prefix --target gnulinux ocl-basic
./tools/test-package.sh --prefix /tmp/orocos-dual-publication-20260808/prefix --target gnulinux ocl-integration
```

Expected: all seven commands exit zero. The `rtt-core` result includes
`mqueue-test` and `mqueue_archive_test`; the OPC UA result includes every
`rtt_opcua_*_test` and `ocl_opcua_deployment_*` case.

- [ ] **Step 4: Record the local commit IDs**

Run `git -C "$repository" rev-parse "$branch"` for every matrix entry and
save the ten full commit IDs in the execution transcript. These are the
expected remote results used in Tasks 2, 3, and 5.

### Task 2: Publish canonical branches to liufang-robot

**Files:**
- Modify local Git configuration only: maintained package remote definitions
  and branch upstreams

**Interfaces:**
- Consumes: verified branches and expected commit IDs from Task 1.
- Produces: `liufang-robot` default branches at those exact commits.

- [ ] **Step 1: Normalize the canonical remote in each checkout**

Use these URLs:

```text
.                                  https://github.com/liufang-robot/rock-orocos.git
toolchain/farbot                   https://github.com/liufang-robot/farbot.git
toolchain/rtlog-cpp                https://github.com/liufang-robot/rtlog-cpp.git
toolchain/tools/rtt                https://github.com/liufang-robot/rtt.git
toolchain/tools/rtt_opcua          https://github.com/liufang-robot/rtt_opcua.git
toolchain/tools/ocl                https://github.com/liufang-robot/ocl.git
toolchain/tools/orogen             https://github.com/liufang-robot/tools-orogen.git
toolchain/tools/typelib            https://github.com/liufang-robot/tools-typelib.git
toolchain/tools/utilmm             https://github.com/liufang-robot/utilmm.git
toolchain/tools/rtt_typelib        https://github.com/liufang-robot/tools-rtt_typelib.git
```

For each checkout, add `liufang` when absent or set its URL when present:

```bash
if git -C "$repository" remote get-url liufang >/dev/null 2>&1; then
  git -C "$repository" remote set-url liufang "$liufang_url"
else
  git -C "$repository" remote add liufang "$liufang_url"
fi
```

- [ ] **Step 2: Fetch and enforce fast-forward publication**

For each checkout:

```bash
git -C "$repository" fetch --no-tags liufang \
  "refs/heads/$branch:refs/remotes/liufang/$branch"
git -C "$repository" merge-base --is-ancestor "liufang/$branch" "$branch"
```

Expected: the ancestor check exits zero. Any failure stops publication and is
reviewed without pushing.

- [ ] **Step 3: Push the canonical default branches**

For each checkout:

```bash
git -C "$repository" push liufang "$branch:$branch"
git -C "$repository" branch --set-upstream-to="liufang/$branch" "$branch"
```

Expected: each push is a fast-forward or reports `Everything up-to-date`.

- [ ] **Step 4: Verify canonical remote commit IDs**

For each repository:

```bash
git ls-remote "$liufang_url" "refs/heads/$branch"
```

Expected: the reported commit equals the Task 1 commit for that package.

### Task 3: Create and synchronize OptimalCNC package repositories

**Files:**
- Modify local Git configuration only: add or normalize `optimalcnc` remotes
- Create remote repositories: `OptimalCNC/farbot`, `OptimalCNC/rtlog-cpp`,
  `OptimalCNC/rtt_opcua`

**Interfaces:**
- Consumes: canonical package commits verified in Task 2.
- Produces: nine self-contained OptimalCNC package repositories on their
  approved default branches.

- [ ] **Step 1: Confirm GitHub authentication and repository visibility**

Run:

```bash
gh auth status
gh repo view liufang-robot/farbot --json visibility,defaultBranchRef
gh repo view liufang-robot/rtlog-cpp --json visibility,defaultBranchRef
gh repo view liufang-robot/rtt_opcua --json visibility,defaultBranchRef
```

Expected: authentication is active; all three source repositories are public
with default branches `master`, `main`, and `dev` respectively.

- [ ] **Step 2: Create only the missing public repositories**

First run `gh repo view` for each target. Only when it reports that the
repository does not exist, run:

```bash
gh repo create OptimalCNC/farbot --public --description "Fast real-time-safe buffer ownership transfer"
gh repo create OptimalCNC/rtlog-cpp --public --description "Bounded real-time logging support for Orocos RTT"
gh repo create OptimalCNC/rtt_opcua --public --description "Native OPC UA transport and object model for Orocos RTT"
```

Expected: each target repository exists and is public. Do not replace an
existing repository.

- [ ] **Step 3: Normalize OptimalCNC remotes**

Use these URLs:

```text
toolchain/farbot                   https://github.com/OptimalCNC/farbot.git
toolchain/rtlog-cpp                https://github.com/OptimalCNC/rtlog-cpp.git
toolchain/tools/rtt                https://github.com/OptimalCNC/rtt.git
toolchain/tools/rtt_opcua          https://github.com/OptimalCNC/rtt_opcua.git
toolchain/tools/ocl                https://github.com/OptimalCNC/ocl.git
toolchain/tools/orogen             https://github.com/OptimalCNC/tools-orogen.git
toolchain/tools/typelib            https://github.com/OptimalCNC/tools-typelib.git
toolchain/tools/utilmm             https://github.com/OptimalCNC/utilmm.git
toolchain/tools/rtt_typelib        https://github.com/OptimalCNC/tools-rtt_typelib.git
```

Add `optimalcnc` when absent or set its URL when present. Do not change the
package branch's `liufang` upstream:

```bash
if git -C "$repository" remote get-url optimalcnc >/dev/null 2>&1; then
  git -C "$repository" remote set-url optimalcnc "$optimalcnc_url"
else
  git -C "$repository" remote add optimalcnc "$optimalcnc_url"
fi
```

- [ ] **Step 4: Verify existing branches are fast-forwardable**

For a non-empty OptimalCNC repository:

```bash
git -C "$repository" fetch --no-tags optimalcnc \
  "refs/heads/$branch:refs/remotes/optimalcnc/$branch"
git -C "$repository" merge-base --is-ancestor "optimalcnc/$branch" "$branch"
```

Expected: the ancestor check exits zero. For a newly created empty repository,
the missing remote branch is expected and the first push establishes it.

- [ ] **Step 5: Push package branches without force**

For each of the nine package repositories:

```bash
git -C "$repository" push optimalcnc "$branch:$branch"
```

Expected: existing branches fast-forward and new branches are created. No push
command contains `--force`, `--force-with-lease`, or a leading `+` refspec.

- [ ] **Step 6: Verify package commit IDs and defaults**

Run `git ls-remote` for all nine OptimalCNC URLs and compare each branch commit
with Task 1. For the three new repositories, also run:

```bash
gh repo view OptimalCNC/farbot --json visibility,defaultBranchRef
gh repo view OptimalCNC/rtlog-cpp --json visibility,defaultBranchRef
gh repo view OptimalCNC/rtt_opcua --json visibility,defaultBranchRef
```

Expected: repositories are public and default branches are `master`, `main`,
and `dev`. If GitHub did not select the only pushed branch as default, set it
explicitly with `gh repo edit OWNER/REPO --default-branch BRANCH`.

### Task 4: Build the OptimalCNC root policy lineage

**Files:**
- Modify: `autoproj/overrides.yml`
- Modify: `tools/check-autoproj-policy.rb`
- Modify: `docs/src/package-policy.md`

**Interfaces:**
- Consumes: canonical root `main` published in Task 2 and package repositories
  published in Task 3.
- Produces: one locally reviewed commit whose live package URLs consistently
  select `OptimalCNC`.

- [ ] **Step 1: Create an isolated local worktree**

Use the `superpowers:using-git-worktrees` skill. From the root repository:

```bash
git worktree add -b sync/optimalcnc-main-20260808 \
  .worktrees/optimalcnc-publication main
```

No branch named `sync/optimalcnc-main-20260808` is pushed to a remote.

- [ ] **Step 2: Change only Autoproj source selection and observe policy RED**

In the worktree, replace `https://github.com/liufang-robot/` with
`https://github.com/OptimalCNC/` for the nine maintained fork entries in
`autoproj/overrides.yml`. Do not alter the official `open62541` or
`open62541pp` URLs.

Run:

```bash
ruby tools/check-autoproj-policy.rb
```

Expected: FAIL because `expected_sources` still requires the nine
`liufang-robot` URLs. This proves the checker detects policy drift.

- [ ] **Step 3: Update the policy checker and active policy documentation**

In `tools/check-autoproj-policy.rb`, change exactly the nine maintained fork
URLs in `expected_sources` to their `OptimalCNC` equivalents. Keep these two
official OPC UA selections unchanged:

```ruby
"open62541" => { "url" => "https://github.com/open62541/open62541.git", "tag" => "v1.4.15" },
"open62541pp" => { "url" => "https://github.com/open62541pp/open62541pp.git", "tag" => "v0.21.2" },
```

In `docs/src/package-policy.md`, change the active `rtt_opcua` source-policy
cell from `` `liufang-robot` upstream `` to `` `OptimalCNC` upstream ``.
Historical design, plan, and test-result documents are not rewritten.

- [ ] **Step 4: Run the OptimalCNC policy GREEN gate**

Run from the worktree:

```bash
ruby tools/check-repository-policy.rb
ruby tools/check-autoproj-policy.rb
ruby tools/check-clean-room-docker.rb
ruby tools/check-native-ci.rb
ruby tools/check-package-tests-ci.rb
ruby tools/check-cpp20-policy.rb
git diff --check
```

Expected: every command exits zero.

- [ ] **Step 5: Review and commit only the organization policy**

Run:

```bash
git diff -- autoproj/overrides.yml tools/check-autoproj-policy.rb docs/src/package-policy.md
git status --short
git add autoproj/overrides.yml tools/check-autoproj-policy.rb docs/src/package-policy.md
git commit -m "build: select OptimalCNC maintenance forks"
```

Expected: exactly the three listed files are committed.

### Task 5: Publish and verify the OptimalCNC root

**Files:**
- No source edits
- Remove after verification: local worktree
  `.worktrees/optimalcnc-publication` and local branch
  `sync/optimalcnc-main-20260808`

**Interfaces:**
- Consumes: the OptimalCNC policy commit from Task 4.
- Produces: a verified self-contained `OptimalCNC/rock-orocos` `main` and a
  clean canonical local workspace.

- [ ] **Step 1: Verify the remote root can fast-forward**

From the publication worktree:

```bash
git fetch --no-tags origin refs/heads/main:refs/remotes/origin/main
git merge-base --is-ancestor origin/main HEAD
```

Expected: the ancestor check exits zero. `origin` is the existing
`OptimalCNC/rock-orocos` remote in this root repository.

- [ ] **Step 2: Push only to the remote default branch**

Run:

```bash
git push origin HEAD:main
```

Expected: `OptimalCNC/rock-orocos/main` fast-forwards to the organization
policy commit. No `sync/*` branch is created remotely.

- [ ] **Step 3: Verify both root policies remotely**

Run:

```bash
git ls-remote https://github.com/liufang-robot/rock-orocos.git refs/heads/main
git ls-remote https://github.com/OptimalCNC/rock-orocos.git refs/heads/main
```

Expected: the liufang branch equals canonical local `main`; the OptimalCNC
branch equals the Task 4 policy commit and contains canonical `main` as an
ancestor.

- [ ] **Step 4: Verify all eighteen package branch endpoints**

Query the two organization URLs for each of the nine maintained packages.
Expected: every liufang and OptimalCNC package branch resolves to the same Task
1 commit ID. Query the three official dependency URLs and confirm their pinned
tags remain `v1.4.15`, `v0.21.2`, and `v3.2.0` where selected.

Run:

```bash
git ls-remote https://github.com/liufang-robot/farbot.git refs/heads/master
git ls-remote https://github.com/OptimalCNC/farbot.git refs/heads/master
git ls-remote https://github.com/liufang-robot/rtlog-cpp.git refs/heads/main
git ls-remote https://github.com/OptimalCNC/rtlog-cpp.git refs/heads/main
git ls-remote https://github.com/liufang-robot/rtt.git refs/heads/dev
git ls-remote https://github.com/OptimalCNC/rtt.git refs/heads/dev
git ls-remote https://github.com/liufang-robot/rtt_opcua.git refs/heads/dev
git ls-remote https://github.com/OptimalCNC/rtt_opcua.git refs/heads/dev
git ls-remote https://github.com/liufang-robot/ocl.git refs/heads/dev
git ls-remote https://github.com/OptimalCNC/ocl.git refs/heads/dev
git ls-remote https://github.com/liufang-robot/tools-orogen.git refs/heads/dev
git ls-remote https://github.com/OptimalCNC/tools-orogen.git refs/heads/dev
git ls-remote https://github.com/liufang-robot/tools-typelib.git refs/heads/dev
git ls-remote https://github.com/OptimalCNC/tools-typelib.git refs/heads/dev
git ls-remote https://github.com/liufang-robot/utilmm.git refs/heads/dev
git ls-remote https://github.com/OptimalCNC/utilmm.git refs/heads/dev
git ls-remote https://github.com/liufang-robot/tools-rtt_typelib.git refs/heads/dev
git ls-remote https://github.com/OptimalCNC/tools-rtt_typelib.git refs/heads/dev
git ls-remote https://github.com/open62541/open62541.git refs/tags/v1.4.15
git ls-remote https://github.com/open62541pp/open62541pp.git refs/tags/v0.21.2
git ls-remote https://github.com/rock-core/tools-utilrb.git refs/tags/v3.2.0
```

- [ ] **Step 5: Clean up the local publication worktree**

After every remote verification passes, run from the main repository:

```bash
git worktree remove .worktrees/optimalcnc-publication
git branch -d sync/optimalcnc-main-20260808
git worktree prune
```

Expected: the temporary local publication branch and worktree are gone; root
`main` still tracks `liufang/main`; `.tb_history` remains untracked and is not
committed.

- [ ] **Step 6: Record the publication result**

Report:

- the ten `liufang-robot` branch commit IDs;
- the ten `OptimalCNC` branch commit IDs;
- the three newly created repository URLs;
- the two root policy commit IDs;
- every validation command and its pass/fail count;
- any remote branch protection or permission behavior encountered.

After recording the result, remove the explicit validation directory:

```bash
rm -rf -- /tmp/orocos-dual-publication-20260808
```
