# Xenomai 3 Integration

This page is the maintainer playbook for carrying a Xenomai 3 capable RTT
target in the `liufang-robot/*` fork set while keeping `orocos-rock` as a
standalone toolchain boundary.

The current default install path remains the generic `gnulinux` toolchain. A
Xenomai build is a deliberate variant selected with `--target xenomai`, staged
on explicit branches, and installed to an explicit prefix such as
`~/.orocos`.

## Current Build Status

The local Xenomai 3 build is a no-CORBA build. `orocos-rock` writes
`rtt_corba_implementation: none` into `.autoproj/config.yml`, which makes RTT
configure with `-DENABLE_CORBA=OFF`. OmniORB is not required for the default
Xenomai 3 toolchain build.

The verified local build uses Xenomai 3.3.3 from `/usr/xenomai` and exports:

- `OROCOS_TARGET=xenomai`
- `XENOMAI_DIR=/usr/xenomai`
- `XENOMAI_ROOT_DIR=/usr/xenomai`

The current RTT support is still transitional. It can build and smoke-run on
Xenomai 3 through the native/trank compatibility headers, but it is not yet a
clean Alchemy/POSIX port. Keep the runtime blockers below visible until they
are fixed and tested.

## Compatibility Decision

The old Orocos RTT branch
`orocos-toolchain/rtt:ahoarau-xenomai3-support-v2` is useful as a migration
reference, but it should not be merged directly into `liufang-robot/rtt`.

Use it to recover the intent of the Xenomai 3 port:

- migrate the old Xenomai native skin assumptions to Xenomai 3 Alchemy/POSIX
- use `xeno-config --alchemy`, `--posix`, `--auto-init-solib`, and
  `--no-auto-init` deliberately
- replace old timer calls with the Xenomai 3 Alchemy timer API
- fix condition-variable use so signal and broadcast operations hold the
  associated mutex
- keep TLSF and real-time malloc behavior compatible with the Xenomai 3 link
  model
- define a Xenomai 3 policy for `IRQActivity`

Do not copy the implementation mechanically. The branch was written against an
older RTT baseline, while this workspace carries C++17, rtlog, and Xenomai
compatibility fixes on `liufang-robot/*` `dev` branches.

## Blocking RTT Review Items

The Xenomai 3 RTT fork is not ready for application use until these items are
settled in `liufang-robot/rtt`.

| Area | Required result |
|---|---|
| CMake discovery | Xenomai 3 Alchemy and POSIX flags are represented as normal CMake targets or clearly scoped variables. |
| Shared-library init | Alchemy libraries use the correct auto-init mode for RTT plugins and deployer use. |
| CPU affinity | RTT's CPU mask semantics are converted to `cpu_set_t` correctly. A mask of `0x4` must bind CPU 2, not CPU 4. |
| Task lifetime | The teardown wrapper distinguishes natural termination from forced deletion: use `rt_task_join()` for naturally terminated joinable tasks, or delete then join when cancellation is required. It must not unconditionally delete after join. |
| Periodic tasks | First-shot and overrun behavior are tested with `rt_task_set_periodic()` and `rt_task_wait_period()`. |
| Condition variables | Every wait/signal/broadcast path is audited for the mutex and predicate pairing expected by Xenomai 3. |
| Semaphores | Absolute timeout, relative timeout, and non-blocking paths are covered by tests. |
| TLSF / RT malloc | Real-time allocation support links cleanly and does not fall back to unsafe hot-path allocation. |
| `IRQActivity` | Xenomai 3 either disables this feature explicitly or replaces it with a new RTDM-aware implementation. |

The CPU affinity and task lifetime items are merge blockers. They are easy to
miss because the code can still compile while having the wrong runtime
semantics.

## Branching Plan

Create a staging branch in the RTT fork:

```bash
git remote add orocos https://github.com/orocos-toolchain/rtt.git
git fetch orocos toolchain-2.9 ahoarau-xenomai3-support-v2
git switch -c dev-xeno3 origin/dev
```

Use the old branch only as a range-diff and path-diff source:

```bash
git range-diff orocos/toolchain-2.9...orocos/ahoarau-xenomai3-support-v2 origin/dev...HEAD

git diff orocos/toolchain-2.9...orocos/ahoarau-xenomai3-support-v2 -- \
  config/FindXenomai.cmake \
  config/FindXenomaiPosix.cmake \
  config/check_depend.cmake \
  rtt/CMakeLists.txt \
  rtt/os/xenomai/fosi.h \
  rtt/os/xenomai/fosi_internal.cpp \
  rtt/Activity.cpp \
  rtt/ExecutionEngine.cpp \
  rtt/extras/IRQActivity.cpp \
  rtt/extras/IRQActivity.hpp
```

Split the work into reviewable RTT pull requests:

| PR | Scope |
|---|---|
| A | `FindXenomai*`, dependency checks, and RTT CMake linking. |
| B | `rtt/os/xenomai` Alchemy/POSIX implementation and local shims for CPU masks and task teardown. |
| C | `Activity`, `ExecutionEngine`, condition-variable audit, and `IRQActivity` policy. |
| D | RTT unit tests and stress tests for Xenomai 3 semantics. |
| E | `rock-orocos` branch override, deployment templates, and target-machine validation. |

Only PR E belongs in this repository.

## `rock-orocos` Wiring

The current RTT source pin is:

```yaml
overrides:
  - rtt:
    type: git
    url: https://github.com/liufang-robot/rtt.git
    branch: dev
```

Use a different branch only when the RTT staging branch has passed the checks
below. Keep any staging override explicit and reviewable.

The standard build command is:

```bash
export XENOMAI_DIR=/usr/xenomai
export XENOMAI_ROOT_DIR=/usr/xenomai
export PATH="$XENOMAI_DIR/bin:$PATH"

./tools/setup.sh --prefix ~/.orocos --target xenomai
```

The generated `env.sh` exports `OROCOS_TARGET=xenomai` for this prefix. The
normal `gnulinux` prefix still exports `OROCOS_TARGET=gnulinux`.

`setup.sh` runs `install.sh`, and `install.sh` updates Autoproj-managed source
checkouts before building. If the Xenomai 3 fixes are still only local
uncommitted changes in `toolchain/tools/rtt` or `toolchain/tools/ocl`, use the
no-update maintainer path instead:

```bash
export XENOMAI_DIR=/usr/xenomai
export XENOMAI_ROOT_DIR=/usr/xenomai
export PATH="$XENOMAI_DIR/bin:$PATH"
export OROCOS_TARGET=xenomai

./tools/install-autoproj.sh
./tools/bootstrap.sh --prefix ~/.orocos --target xenomai --skip-osdeps

source tools/common.sh
orocos_rock_require_autoproj
orocos_rock_ensure_workspace_ruby_gems
orocos_rock_configure_target_environment xenomai
orocos_rock_prepare_autoproj_workspace "$HOME/.orocos" none xenomai
orocos_rock_autoproj build --no-interactive

./tools/install-ruby-tools.sh --prefix ~/.orocos
./tools/export-env.sh --prefix ~/.orocos --target xenomai
./tools/validate-install.sh --prefix ~/.orocos --target xenomai
```

Do not use the no-update path as a release substitute. It is only for testing a
workspace that deliberately carries local staged fixes.

## Validation Layers

Use three separate gates. A green compile does not prove real-time behavior.

| Gate | Runs where | Purpose |
|---|---|---|
| Generic package tests | Existing container CI | Keep C++17 and generic Orocos behavior from regressing. |
| Xenomai host smoke | Target machine | Verify Cobalt, Alchemy/POSIX flags, CPU mask expectations, installed prefix, and optional EtherLab access. |
| Real-time regression | Target machine | Exercise RTT activities, ports, EtherCAT loop phase split, latency, and stress behavior. |

Useful target-machine smoke commands are:

```bash
/usr/xenomai/bin/xeno-config --version
/usr/xenomai/bin/xeno-config --skin=native --cflags
/usr/xenomai/bin/xeno-config --skin=posix --cflags
source ~/.orocos/env.sh
echo "$OROCOS_TARGET"
deployer-xenomai --version
latency
xeno-test -p 10
```

Expected minimal output:

```text
xenomai
based on Xenomai/cobalt v3.x
```

The minimum target-machine regression after the RTT patch lands is:

- `latency`
- `xeno-test -p 10`
- a short 1 kHz RTT periodic component test
- a longer 1 kHz RTT periodic component test under system load
- RTT port ping-pong tests for representative payload sizes
- libfakeethercat dry-run lifecycle test
- EtherCAT no-slave smoke test
- EtherCAT real-slave loop test when hardware is connected

Use relative thresholds from the target machine's known-good baseline. The
first pass should fail if worst-case latency or jitter regresses by more than
10 percent, if a periodic task shows sustained overruns, or if any start/stop
or join path deadlocks.

## EtherCAT Phase Rule

Keep the EtherCAT lifecycle split explicit in downstream applications:

- Linux process context: request the master, configure slaves, register PDOs,
  and activate the master.
- Xenomai real-time context: run the periodic receive/process/queue/send loop.

Do not move configuration calls into the real-time cycle just because the RTT
target can now create Xenomai threads.

## Primary References

- Xenomai 3 `xeno-config` manual:
  <https://doc.xenomai.org/v3/html/man1/xeno-config/index.html>
- Xenomai 3 Alchemy task API:
  <https://doc.xenomai.org/v3/html/xeno3prm/group__alchemy__task.html>
- Xenomai 3 Alchemy timer API:
  <https://doc.xenomai.org/v3/html/xeno3prm/group__alchemy__timer.html>
- Xenomai 2 to 3 migration notes:
  <https://doc.xenomai.org/v3/html/MIGRATION/index.html>
