# RTT OPC UA System Dependency Includes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve strict C++20 warnings for maintained `rtt_opcua` code while compiling Orocos RTT and Xenomai 3.3.3 dependency headers through a CMake system-include boundary, then finish the no-update Xenomai installation.

**Architecture:** Split the package's include declarations by ownership: `rtt_opcua` headers remain ordinary public includes and `${OROCOS-RTT_INCLUDE_DIRS}` become system public includes. Prove the boundary with the existing real failing compile and a structured compile-command check, then resume the already-clean Autoproj build without updating sources.

**Tech Stack:** CMake 3.28, GCC 13, C++20, Xenomai 3.3.3, Orocos RTT, Autoproj 2.18+, Ruby JSON/Shellwords, Bash.

## Global Constraints

- Keep `RTT_OPCUA_WARNINGS_AS_ERRORS=ON` in the Autoproj build.
- Keep `-Wall`, `-Wextra`, and `-Wpedantic` for maintained `rtt_opcua` sources.
- Do not add warning-specific suppressions for Xenomai diagnostics.
- Do not modify Orocos RTT, Xenomai, or installed dependency headers for this issue.
- Do not run a source update, force-update, reset, clean, or push any checkout.
- Leave the intentional RTT wakeup patch uncommitted and preserve both RTT stashes.
- Leave the `rtt_opcua` CMake change visible and uncommitted on synchronized `dev`; do not change package refs.
- Build target: `xenomai`; Xenomai prefix: `/usr/xenomai`; install prefix: `/home/metanc/.orocos`.
- Require C++20, RTT `ENABLE_MQ=ON`, and RTT `ENABLE_CORBA=OFF`.
- Keep the preserved first-failure log at `.superpowers/sdd/2026-08-10-xenomai-cpp20-clean-rebuild/task-5-rtt_opcua-first-failure.log`.

---

### Task 1: Classify RTT And Xenomai Includes As Dependencies

**Files:**
- Modify: `toolchain/tools/rtt_opcua/CMakeLists.txt:40-47`
- Inspect: `toolchain/tools/rtt_opcua/build/compile_commands.json`
- Preserve: `.superpowers/sdd/2026-08-10-xenomai-cpp20-clean-rebuild/task-5-rtt_opcua-first-failure.log`

**Interfaces:**
- Consumes: the configured C++20 Xenomai `rtt_opcua` build tree and installed RTT dependency headers under `/home/metanc/.orocos/toolchain`.
- Produces: ordinary public `rtt_opcua` include paths, system public `${OROCOS-RTT_INCLUDE_DIRS}`, and a focused warnings-as-errors build that later Autoproj work can install.

- [ ] **Step 1: Re-run the focused compile to verify the RED boundary**

Run:

```bash
/bin/bash -lc '
set -euo pipefail
cmake --build toolchain/tools/rtt_opcua/build \
  --target orocos-rtt-opcua \
  --parallel 2 2>&1 | \
  tee .superpowers/sdd/2026-08-10-xenomai-cpp20-clean-rebuild/task-5-rtt_opcua-system-includes-red.log
'
```

Expected: FAIL. The log contains `-Werror` diagnostics originating in
`/usr/xenomai/include` and/or installed RTT Xenomai headers, followed by
`cc1plus: all warnings being treated as errors`. It must not contain a
diagnostic originating in a maintained `rtt_opcua` source or header.

- [ ] **Step 2: Split project and dependency include ownership**

Replace the existing `target_include_directories(orocos-rtt-opcua ...)` block
with:

```cmake
target_include_directories(
  orocos-rtt-opcua
  BEFORE
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
target_include_directories(
  orocos-rtt-opcua
  SYSTEM BEFORE
  PUBLIC
    ${OROCOS-RTT_INCLUDE_DIRS}
)
```

Do not change the warning options, C++ standard, transport plugin include
declaration, Autoproj package definitions, or dependency sources.

- [ ] **Step 3: Reconfigure and verify the generated compile boundary**

Run:

```bash
cmake \
  -S toolchain/tools/rtt_opcua \
  -B toolchain/tools/rtt_opcua/build \
  -DRTT_OPCUA_WARNINGS_AS_ERRORS=ON
```

Then validate the real compile command with structured JSON and shell-token
parsing:

```bash
ruby -rjson -rshellwords -e '
entries = JSON.parse(File.read(ARGV.fetch(0)))
entry = entries.find { |item| item.fetch("file").end_with?("/src/client_session.cpp") }
abort "client_session compile command is missing" unless entry
tokens = Shellwords.split(entry.fetch("command"))

%w[-std=c++20 -Wall -Wextra -Wpedantic -Werror].each do |flag|
  abort "missing required flag: #{flag}" unless tokens.include?(flag)
end

own = "/home/metanc/liufang/src/rock-orocos/toolchain/tools/rtt_opcua/include"
abort "project include is not ordinary" unless tokens.include?("-I#{own}")
abort "project include became system" if tokens.each_cons(2).any? { |a, b| a == "-isystem" && b == own }

dependencies = [
  "/home/metanc/.orocos/toolchain/include/orocos",
  "/usr/xenomai/include/trank",
  "/usr/xenomai/include/cobalt",
  "/usr/xenomai/include",
  "/usr/xenomai/include/alchemy"
]
dependencies.each do |path|
  system_pair = tokens.each_cons(2).any? { |a, b| a == "-isystem" && b == path }
  abort "dependency include is not system: #{path}" unless system_pair || tokens.include?("-isystem#{path}")
end

puts "validated rtt_opcua C++20 warning and system-include boundary"
' toolchain/tools/rtt_opcua/build/compile_commands.json
```

Expected: both commands exit `0`; the Ruby validator prints
`validated rtt_opcua C++20 warning and system-include boundary`.

- [ ] **Step 4: Build the maintained library and transport with strict warnings**

Run:

```bash
cmake --build toolchain/tools/rtt_opcua/build \
  --target orocos-rtt-opcua rtt-transport-opcua \
  --parallel 2
```

Expected: PASS with `-std=c++20`, `-Werror`, and no promoted dependency-header
diagnostics.

- [ ] **Step 5: Verify the scoped source diff and preservation boundary**

Run:

```bash
git -C toolchain/tools/rtt_opcua diff --check
git -C toolchain/tools/rtt_opcua status --short --branch
git -C toolchain/tools/rtt diff --check
git -C toolchain/tools/rtt status --short --branch
git -C toolchain/tools/rtt stash list --format="%H %gs"
sha256sum \
  .superpowers/sdd/2026-08-10-xenomai-cpp20-clean-rebuild/task-5-rtt_opcua-first-failure.log
```

Expected: `rtt_opcua` has exactly `M CMakeLists.txt` plus untracked `build/`;
RTT has exactly the approved `rtt/ExecutionEngine.cpp` and
`tests/method_test.cpp` modifications; both retained stash OIDs remain; the
preserved failure-log SHA-256 remains
`4f483090e0370a001123382c2be061907aec50ca1dc44f9d1b4a4428b6f824d9`.

Do not commit the nested package change.

---

### Task 2: Resume The No-Update Build And Validate The Prefix

**Files:**
- Generate: package-local `build/` directories under `toolchain/`
- Generate: `/home/metanc/.orocos/toolchain/`
- Generate: `/home/metanc/.orocos/env.sh`
- Generate: `/home/metanc/.orocos/dev-env.sh`
- Inspect: `toolchain/tools/rtt_opcua/build/compile_commands.json`

**Interfaces:**
- Consumes: Task 1's focused green `rtt_opcua` build, the partial fresh prefix, and the already-resolved OS dependencies.
- Produces: a complete validated C++20 Xenomai prefix with `deployer-opcua-xenomai`, `ctaskbrowser-opcua-xenomai`, mqueue transport, `orogen`, and `typegen`.

- [ ] **Step 1: Resume the selected Autoproj build without updating sources**

Run exactly one build command:

```bash
/bin/bash -lc '
set -euo pipefail
export PYTHONPATH="${PYTHONPATH-}"
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

Expected: all selected packages compile and install successfully. The command
must not invoke `autoproj update` or another source-update path. If it fails,
preserve the first failing package log and return to systematic root-cause
analysis before any retry.

- [ ] **Step 2: Re-verify the final `rtt_opcua` compiler boundary**

Run:

```bash
ruby -rjson -rshellwords -e '
entries = JSON.parse(File.read(ARGV.fetch(0)))
entry = entries.find { |item| item.fetch("file").end_with?("/src/client_session.cpp") }
abort "client_session compile command is missing" unless entry
tokens = Shellwords.split(entry.fetch("command"))

%w[-std=c++20 -Wall -Wextra -Wpedantic -Werror].each do |flag|
  abort "missing required flag: #{flag}" unless tokens.include?(flag)
end

own = "/home/metanc/liufang/src/rock-orocos/toolchain/tools/rtt_opcua/include"
abort "project include is not ordinary" unless tokens.include?("-I#{own}")
abort "project include became system" if tokens.each_cons(2).any? { |a, b| a == "-isystem" && b == own }

dependencies = [
  "/home/metanc/.orocos/toolchain/include/orocos",
  "/usr/xenomai/include/trank",
  "/usr/xenomai/include/cobalt",
  "/usr/xenomai/include",
  "/usr/xenomai/include/alchemy"
]
dependencies.each do |path|
  system_pair = tokens.each_cons(2).any? { |a, b| a == "-isystem" && b == path }
  abort "dependency include is not system: #{path}" unless system_pair || tokens.include?("-isystem#{path}")
end

puts "validated rtt_opcua C++20 warning and system-include boundary"
' toolchain/tools/rtt_opcua/build/compile_commands.json
```

Expected: PASS after the complete Autoproj build; strict maintained-source
flags and system dependency includes remain configured.

- [ ] **Step 3: Stage Ruby generator tools and export stable environments**

Run:

```bash
./tools/install-ruby-tools.sh --prefix /home/metanc/.orocos
XENOMAI_DIR=/usr/xenomai \
XENOMAI_ROOT_DIR=/usr/xenomai \
./tools/export-env.sh --prefix /home/metanc/.orocos --target xenomai
```

Expected: `/home/metanc/.orocos/env.sh` and
`/home/metanc/.orocos/dev-env.sh` exist and reference the fresh prefix;
installed `orogen` and `typegen` resolve below `/home/metanc/.orocos`.

- [ ] **Step 4: Validate the installed-prefix contract**

Run:

```bash
XENOMAI_DIR=/usr/xenomai \
XENOMAI_ROOT_DIR=/usr/xenomai \
./tools/validate-install.sh \
  --prefix /home/metanc/.orocos \
  --target xenomai
```

Expected: exit `0` with
`Validated Orocos/Rock xenomai install prefix: /home/metanc/.orocos`. The
validator confirms `deployer-xenomai`, `deployer-opcua-xenomai`,
`ctaskbrowser-opcua-xenomai`, the xenomai mqueue transport, OPC UA metadata,
`orogen`, and `typegen`.

- [ ] **Step 5: Verify source, patch, stash, and ref preservation**

Run:

```bash
git status --short --branch
git -C toolchain/tools/rtt_opcua status --short --branch
git -C toolchain/tools/rtt_opcua diff --check
git -C toolchain/tools/rtt status --short --branch
git -C toolchain/tools/rtt diff --check
git -C toolchain/tools/rtt stash list --format="%H %gs"

while read -r repo expected; do
  actual="$(git -C "$repo" rev-parse HEAD)"
  if test "$actual" != "$expected"; then
    printf "ref changed: %s expected=%s actual=%s\n" \
      "$repo" "$expected" "$actual" >&2
    exit 1
  fi
done <<'REFS'
toolchain/farbot 09fd406eef4778511e85b569e3e75cad3d5cf608
toolchain/rtlog-cpp 5842ca36c69ad4ba34321eda80891c832298f161
toolchain/tools/rtt 3140361114c470025ceb7af755073f9d9896db39
toolchain/open62541 45e4cd3ef6c79a8e503d37c9f5c89fefe90d99db
toolchain/open62541pp b1696768b26a12d0f40fdac5ec62ad78d25fa236
toolchain/tools/rtt_opcua 770b5089902f77c6de2a47fbbb989579d1caf087
toolchain/tools/ocl d465bb83f6870503a53571a93a36adf01a8cdfc1
toolchain/tools/orogen 546b1990221a7ebc86e787ea15a2e322c7e19d08
toolchain/tools/typelib 8998f8f24d58d0e450c3a6bf1cccc9552e184980
toolchain/tools/utilmm 9bab24d43a691137e2f1cd50c742cdd9482d3c86
toolchain/tools/utilrb 0028fac920eac5d5f9332c3a3438dcf4b7562953
toolchain/tools/rtt_typelib c5b345a22036019f8ec4ed176299bab3b80aae0a
REFS
```

Expected: root has no new tracked source change; `rtt_opcua` still has only
the approved uncommitted `CMakeLists.txt` change; RTT still has exactly the two
approved uncommitted wakeup files; both RTT stash OIDs remain; the exact ref
loop exits `0` for all selected package HEADs.

Do not run the parent plan's Task 6 RTT regression suite or Task 7 OPC UA
loopback smoke test in this task.
