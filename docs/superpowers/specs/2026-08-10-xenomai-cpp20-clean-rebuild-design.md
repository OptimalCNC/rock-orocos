# Xenomai C++20 Clean Rebuild Design

Date: 2026-08-10

Status: Approved for implementation

## Purpose

Synchronize this `orocos-rock` workspace and its Autoproj-managed source
checkouts with their configured remote branches and tags, preserve and merge
the existing local RTT fix, and produce a clean C++20 Xenomai installation at
`/home/metanc/.orocos` that includes the native OPC UA deployer.

The expected installed commands include:

- `deployer-xenomai`
- `deployer-opcua-xenomai`
- `ctaskbrowser-opcua-xenomai`
- `orogen`
- `typegen`

## Current State

The remote `orocos-rock` `main` branch contains the coordinated C++20 and
native OPC UA work. Its package policy adds `open62541`, `open62541pp`, and
`rtt_opcua`, removes `stdint_typekit` from the selected layout, and keeps CORBA
disabled.

The existing workspace is configured for Xenomai 3.3.3 at `/usr/xenomai` and
uses GCC 13. The current install prefix is `/home/metanc/.orocos`.

The RTT checkout has intentional, uncommitted changes on
`fix-execution-engine-nested-ownthread-wakeup`:

- `rtt/ExecutionEngine.cpp` makes producer notification and waiter queue
  inspection coherent under `msg_lock`: producers broadcast while holding the
  lock, and `waitAndProcessMessages()` waits only when its predicate is false
  and the message queue is empty.
- `tests/method_test.cpp` deterministically injects real message work after the
  waiter's first empty drain and verifies that the waiter processes it without
  requiring a second notification.

All other selected source checkouts have no tracked edits. Package-local build
directories and a root `CMakeFiles/` directory are generated artifacts.

## Goals

- Base the root maintenance branch on the current remote `main` commit.
- Synchronize every selected package to the branch or tag in the updated
  Autoproj policy.
- Retain a recoverable copy of the local RTT edits throughout the operation.
- Reapply the RTT behavior and regression to the updated C++20 RTT source.
- Remove prior build and installation artifacts before compilation.
- Install a fresh Xenomai prefix at `/home/metanc/.orocos` without retaining
  the old prefix.
- Verify the normal deployer, native OPC UA deployer and browser, RTT mqueue
  transport, generator tools, the RTT regression, and an actual loopback OPC
  UA listener.

## Non-Goals

- Change the remote package policy or introduce new dependency versions.
- Push directly to remote `main` or any package remote.
- Delete source checkouts, Git history, stashes, or Autoproj's Ruby bootstrap
  state.
- Preserve the old `/home/metanc/.orocos` installation.
- Run the full Xenomai latency, stress, or hardware regression suite.
- Enable CORBA or non-loopback OPC UA access.

## Source Synchronization

Root work proceeds on `codex/xenomai-cpp20-clean-rebuild`, based on current
`origin/main`. This keeps local design and execution records off `main` while
using the exact remote toolchain policy.

Before package updates, save the RTT working changes in a named Git stash. Do
not drop that stash after applying it. Record its object identity so the
original patch remains recoverable even if conflict resolution is needed.

Bootstrap and reconfigure Autoproj from the updated root policy, then update
the selected source packages before applying the RTT patch. The authoritative
source selections are:

| Package | Selection |
| --- | --- |
| `farbot` | `liufang-robot/farbot`, branch `master` |
| `rtlog-cpp` | `liufang-robot/rtlog-cpp`, branch `main` |
| `rtt` | `liufang-robot/rtt`, branch `dev` |
| `open62541` | upstream tag `v1.4.15` |
| `open62541pp` | upstream tag `v0.21.2` |
| `rtt_opcua` | `liufang-robot/rtt_opcua`, branch `dev` |
| `ocl` | `liufang-robot/ocl`, branch `dev` |
| `orogen` | `liufang-robot/tools-orogen`, branch `dev` |
| `typelib` | `liufang-robot/tools-typelib`, branch `dev` |
| `utilmm` | `liufang-robot/utilmm`, branch `dev` |
| `utilrb` | package-set upstream selection |
| `rtt_typelib` | `liufang-robot/tools-rtt_typelib`, branch `dev` |

After the update, move the local RTT feature branch from its old base to the
updated `dev` head and apply the saved stash. Resolve conflicts only in the two
original files unless an updated API requires a directly related change. If
the new RTT source already implements equivalent locking, keep the regression
coverage and avoid duplicating the implementation.

The retained producer-side lock alone is insufficient. The waiter can drain an
empty queue, lose a producer broadcast before it begins waiting, and then sleep
while the queue is nonempty. The complete protocol keeps the producer broadcast
under `msg_lock` and, after each drain, checks both the completion predicate and
message-queue emptiness under that same lock. A true predicate returns; an empty
queue waits; queued work releases the lock and loops back to `processMessages()`.

The regression uses only the existing protected `ExecutionEngine` test
boundary. A test engine running on an RTT `Activity` injects one real disposable
into `mqueue` on the post-drain predicate call. A two-second `std::future` bound
captures failure before an unconditional cancel, locked broadcast, activity
stop, and join. This creates the missed-notification state deterministically,
without a production test hook, mocks, probabilistic repetition, or an
unbounded hang.

No source update runs after this merge and before compilation. This prevents
Autoproj from replacing or rejecting the intentional RTT working state.

## Autoproj Bootstrap Recovery

The repository's lightweight bootstrap keeps using the already installed
user-level Autoproj gem instead of replacing it with a second workspace-local
gem installation. The generated workspace state must nevertheless include a
Ruby-compatible `.autoproj/bin/autoproj` launcher because Autoproj Stage 2
invokes that exact path through the Ruby interpreter.

`orocos_rock_prepare_autoproj_workspace` generates the launcher alongside its
existing `bundle`, `bundler`, and `ruby` wrappers. The launcher records the
workspace root and Gemfile, exposes the same user and default gem paths used by
`orocos_rock_autoproj`, activates the compatible Facets release, and loads the
installed Autoproj executable. It is generated workspace state and is not
committed.

This does not make Stage 2 part of every normal bootstrap. In particular,
`bootstrap.sh --skip-osdeps` must continue to skip dependency installation.
For this recovery, rerun the already approved Stage 2 command once after the
launcher exists. Stage 2 must complete its environment export and dependency
phase before destructive cleanup or compilation begins.

Regression coverage must first fail when the launcher generation is absent,
then pass after the fix. Integration verification invokes the generated file
through Ruby, matching Stage 2, and confirms that Stage 2 completes without
changing selected source refs or the retained RTT stash.

## Clean Build Boundary

Before deletion, enumerate and review the exact package-local `build/`
directories. Remove only:

- reviewed package-local build directories under the managed package roots;
- build directories for obsolete `log4cpp` and `stdint_typekit` checkouts;
- the root generated `CMakeFiles/` directory; and
- `/home/metanc/.orocos`.

Do not delete package source directories, `.git` directories, `.autoproj`, the
RTT stash, or unrelated files. The obsolete `log4cpp` and `stdint_typekit`
source checkouts may remain, but they are not part of the updated manifest and
must not be built or installed.

The old prefix is removed without a backup, as requested. Available disk space
is checked again after cleanup and before compilation.

## Build Flow

Export the Xenomai discovery environment explicitly:

```bash
export XENOMAI_DIR=/usr/xenomai
export XENOMAI_ROOT_DIR=/usr/xenomai
export PATH="/usr/xenomai/bin:$PATH"
export OROCOS_TARGET=xenomai
```

Run the root repository and Autoproj policy checks, including the C++20 policy
check, after all selected sources are present and the RTT patch is merged.
Resolve source-declared OS dependencies through Autoproj.

Build the selected layout using the documented no-update maintainer path. Then
stage the Ruby generator tools, export `env.sh` and `dev-env.sh` for the Xenomai
target, and run the installed-prefix validator.

## Failure Handling

- Use fast-forward synchronization. Do not force-update or reset a checkout.
- Stop before cleanup if any unexpected tracked package edits appear.
- Keep the RTT stash after applying it.
- Limit merge resolution to the approved RTT behavior and regression.
- Preserve build and Autoproj logs after a failure.
- If disk space is insufficient, stop and report the measured requirement;
  do not broaden cleanup beyond the approved targets.
- Do not restore the old prefix after a failure because no backup was
  requested.

## Verification

Verification has five layers:

1. Repository and Autoproj policy checks pass, including C++20 enforcement.
2. Selected checkouts match their configured remote branch or tag, except for
   the visible intentional RTT patch.
3. `tools/validate-install.sh --prefix /home/metanc/.orocos --target xenomai`
   verifies the Xenomai deployer, OPC UA deployer and browser, target-specific
   mqueue transport, OPC UA pkg-config packages, `orogen`, and `typegen`.
4. The focused `testWaitAndProcessMessagesDoesNotSleepWithQueuedWork` RTT
   regression passes against the updated C++20/Xenomai build.
5. A bounded `deployer-opcua-xenomai` process executes `opcua.start()`, remains
   healthy, and exposes its endpoint only on loopback. The process is stopped
   cleanly after the listener check.

The loopback smoke test uses a temporary `.ops` file outside the repository.
It does not enable non-loopback access or require application-specific
components.

## Acceptance Criteria

The operation is complete when the fresh `/home/metanc/.orocos` prefix passes
all five verification layers, the selected target is reported as `xenomai`,
and the RTT feature checkout contains the merged local changes with its
recovery stash still available.
