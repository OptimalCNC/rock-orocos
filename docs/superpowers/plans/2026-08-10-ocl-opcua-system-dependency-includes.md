# OCL OPC UA System Dependency Includes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep strict C++20 warnings on all four OCL OPC UA targets while classifying installed `rtt_opcua`, Orocos RTT, and Xenomai headers as target-local system dependencies, then complete the no-update Xenomai installation.

**Architecture:** Mark `${RTT_OPCUA_INCLUDE_DIRS}` as `SYSTEM PRIVATE` on the deployment library, deployment test, deployer, and TaskBrowser client while leaving OCL source and generated paths ordinary. Prove all four target boundaries through structured compile-command inspection and focused builds before resuming the partial clean Autoproj build.

**Tech Stack:** CMake 3.28, GCC 13, C++20, Xenomai 3.3.3, Orocos RTT/OCL, `rtt_opcua`, Autoproj 2.18+, Ruby JSON/Shellwords, Bash.

## Global Constraints

- Keep `-Wall -Wextra -Wpedantic -Werror` on all four OCL OPC UA targets.
- Do not add warning-specific suppressions for Xenomai diagnostics.
- Do not modify `rtt_opcua`, Orocos RTT, Xenomai, installed headers, or exported dependency metadata for this issue.
- Do not run a source update, force-update, reset, clean, or push any checkout.
- Leave OCL at `d465bb83f6870503a53571a93a36adf01a8cdfc1` with only the approved diffs in `bin/CMakeLists.txt` and `deployment/CMakeLists.txt` visible and uncommitted.
- Preserve the reviewed uncommitted `rtt_opcua` CMake diff at `770b5089902f77c6de2a47fbbb989579d1caf087`.
- Leave the intentional RTT wakeup patch uncommitted at `3140361114c470025ceb7af755073f9d9896db39` and preserve both RTT stashes.
- Build target: `xenomai`; Xenomai prefix: `/usr/xenomai`; install prefix: `/home/metanc/.orocos`.
- Require C++20, RTT `ENABLE_MQ=ON`, and RTT `ENABLE_CORBA=OFF`.
- Preserve `.superpowers/sdd/2026-08-10-rtt-opcua-system-dependency-includes/task-2-first-failure-ocl-build.log` with SHA-256 `9cc3c369a64596e2e7d9095a48d5b571093eb7b143cd352d2b9e018002f1a47c`.

---

### Task 1: Classify All Four OCL OPC UA Dependency Boundaries

**Files:**
- Modify: `toolchain/tools/ocl/bin/CMakeLists.txt:41-63`
- Modify: `toolchain/tools/ocl/deployment/CMakeLists.txt:36-76`
- Inspect: `toolchain/tools/ocl/build/compile_commands.json`
- Preserve: `.superpowers/sdd/2026-08-10-rtt-opcua-system-dependency-includes/task-2-first-failure-ocl-build.log`
- Preserve: `.superpowers/sdd/2026-08-10-ocl-opcua-system-dependency-includes/task-1-ocl-opcua-system-includes-red.log`

**Interfaces:**
- Consumes: the configured C++20 Xenomai OCL build tree and installed `rtt_opcua`/RTT dependencies in the partial fresh prefix.
- Produces: ordinary OCL-owned include paths, system-private dependency paths on all four strict OPC UA targets, and focused green builds for the library, test, deployer, and client.

- [x] **Step 1: Verify the captured RED boundary**

The focused build was already run before the plan amendment:

```bash
/bin/bash -lc '
set -euo pipefail
cmake --build toolchain/tools/ocl/build \
  --target deployer-opcua ctaskbrowser-opcua \
  --parallel 2 2>&1 | \
  tee .superpowers/sdd/2026-08-10-ocl-opcua-system-dependency-includes/task-1-ocl-opcua-system-includes-red.log
'
```

Expected: FAIL with `-Werror` diagnostics originating in
`/usr/xenomai/include` and/or installed RTT Xenomai headers. The log must show
no diagnostic originating in maintained OCL source or headers. The captured
command exited `2`, failed in `orocos-ocl-deployment-opcua`, and the log has
SHA-256 `e660ca655d897251ef54423c5c160a9da2fbb16f0d8db93840d7c450ea3a1ae8`.

- [x] **Step 2: Mark both executable dependencies as system-private**

Change only the two existing calls in `toolchain/tools/ocl/bin/CMakeLists.txt`:

```cmake
target_include_directories(deployer-opcua SYSTEM PRIVATE
  ${RTT_OPCUA_INCLUDE_DIRS})
```

and:

```cmake
target_include_directories(ctaskbrowser-opcua SYSTEM PRIVATE
  ${RTT_OPCUA_INCLUDE_DIRS})
```

Do not change the C++ standard, strict warning options, link dependencies,
Orocos helper macros, other OCL targets, or any dependency source. These two
edits are already applied and their generated commands passed the structured
validator.

- [ ] **Step 3: Mark the deployment library and test dependencies as system-private**

Change only the two existing calls in
`toolchain/tools/ocl/deployment/CMakeLists.txt`:

```cmake
TARGET_INCLUDE_DIRECTORIES(orocos-ocl-deployment-opcua SYSTEM PRIVATE
  ${RTT_OPCUA_INCLUDE_DIRS})
```

and:

```cmake
target_include_directories(ocl_opcua_deployment_test SYSTEM PRIVATE
  ${RTT_OPCUA_INCLUDE_DIRS})
```

Do not change `BUILD_TESTING`, the C++ standard, strict warning options, link
dependencies, installed headers, or any other OCL target.

- [ ] **Step 4: Reconfigure OCL and verify all four real compile commands**

Run:

```bash
cmake -S toolchain/tools/ocl -B toolchain/tools/ocl/build
rg '^BUILD_TESTING:BOOL=ON$' toolchain/tools/ocl/build/CMakeCache.txt
```

Then run:

```bash
ruby -rjson -rshellwords -e '
entries = JSON.parse(File.read(ARGV.fetch(0)))
common_ordinary = [
  "/home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl",
  "/home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl/build/ocl",
  "/home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl/build"
]
specs = {
  "deployer-opcua" => [
    "/bin/deployer.cpp",
    "CMakeFiles/deployer-opcua.dir/",
    common_ordinary + [
      "/home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl/build/bin"
    ]
  ],
  "ctaskbrowser-opcua" => [
    "/bin/ctaskbrowser-opcua.cpp",
    "CMakeFiles/ctaskbrowser-opcua.dir/",
    common_ordinary + [
      "/home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl/build/bin"
    ]
  ],
  "orocos-ocl-deployment-opcua" => [
    "/deployment/OpcUaDeploymentComponent.cpp",
    "CMakeFiles/orocos-ocl-deployment-opcua.dir/",
    common_ordinary
  ],
  "ocl_opcua_deployment_test" => [
    "/deployment/tests/opcua_deployment_test.cpp",
    "CMakeFiles/ocl_opcua_deployment_test.dir/",
    common_ordinary
  ]
}
dependencies = [
  "/home/metanc/.orocos/toolchain/include/orocos",
  "/usr/xenomai/include/trank",
  "/usr/xenomai/include/cobalt",
  "/usr/xenomai/include",
  "/usr/xenomai/include/alchemy",
  "/home/metanc/.orocos/toolchain/include"
]

specs.each do |target, (suffix, marker, ordinary)|
  entry = entries.find do |item|
    item.fetch("file").end_with?(suffix) &&
      item.fetch("command").include?(marker)
  end
  abort "#{target} compile command is missing" unless entry
  tokens = Shellwords.split(entry.fetch("command"))
  %w[-std=c++20 -Wall -Wextra -Wpedantic -Werror].each do |flag|
    abort "#{target} missing required flag: #{flag}" unless tokens.include?(flag)
  end
  ordinary.each do |path|
    abort "#{target} OCL include is not ordinary: #{path}" unless tokens.include?("-I#{path}")
    system_pair = tokens.each_cons(2).any? { |a, b| a == "-isystem" && b == path }
    abort "#{target} OCL include became system: #{path}" if system_pair || tokens.include?("-isystem#{path}")
  end
  dependencies.each do |path|
    system_pair = tokens.each_cons(2).any? { |a, b| a == "-isystem" && b == path }
    abort "#{target} dependency is not system: #{path}" unless system_pair || tokens.include?("-isystem#{path}")
  end
end

puts "validated all four OCL OPC UA C++20 warning and system-include boundaries"
' toolchain/tools/ocl/build/compile_commands.json
```

Expected: all three commands exit `0`; the cache check prints
`BUILD_TESTING:BOOL=ON` and the Ruby validator prints
`validated all four OCL OPC UA C++20 warning and system-include boundaries`.

- [ ] **Step 5: Build all four OPC UA targets with strict warnings**

Run:

```bash
cmake --build toolchain/tools/ocl/build \
  --target orocos-ocl-deployment-opcua ocl_opcua_deployment_test \
    deployer-opcua ctaskbrowser-opcua \
  --parallel 2
```

Expected: PASS with `-std=c++20 -Wall -Wextra -Wpedantic -Werror` and no
promoted dependency-header diagnostics.

- [ ] **Step 6: Verify the exact OCL diff and all preserved source state**

Run:

```bash
git -C toolchain/tools/ocl diff --check
git -C toolchain/tools/ocl status --short --branch
git -C toolchain/tools/rtt_opcua diff --check
git -C toolchain/tools/rtt_opcua status --short --branch
git -C toolchain/tools/rtt diff --check
git -C toolchain/tools/rtt status --short --branch
git -C toolchain/tools/rtt stash list --format="%H %gs"
sha256sum \
  .superpowers/sdd/2026-08-10-rtt-opcua-system-dependency-includes/task-2-first-failure-ocl-build.log
```

Expected: OCL has exactly `M bin/CMakeLists.txt` and
`M deployment/CMakeLists.txt` plus untracked `build/`;
`rtt_opcua` still has exactly `M CMakeLists.txt` plus untracked `build/`; RTT
still has exactly the approved `rtt/ExecutionEngine.cpp` and
`tests/method_test.cpp` modifications; both stash OIDs remain; the preserved
OCL failure-log hash matches the Global Constraints.

Do not commit either nested package change.

---

### Task 2: Finish The No-Update Build And Validate The Prefix

**Files:**
- Generate: remaining package-local `build/` directories under `toolchain/`
- Complete: `/home/metanc/.orocos/toolchain/`
- Generate: `/home/metanc/.orocos/env.sh`
- Generate: `/home/metanc/.orocos/dev-env.sh`
- Inspect: `toolchain/tools/ocl/build/compile_commands.json`
- Inspect: `toolchain/tools/rtt_opcua/build/compile_commands.json`

**Interfaces:**
- Consumes: Task 1's four focused green OCL targets, the reviewed `rtt_opcua` boundary, and the partial fresh prefix.
- Produces: a complete validated C++20 Xenomai prefix with OPC UA deployer/client tools, mqueue transport, `orogen`, and `typegen`.

- [ ] **Step 1: Resume Autoproj once without updating sources**

Run:

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

Expected: all selected packages compile and install successfully without an
`autoproj update` or other source-update path. If the command fails, preserve
the first failing package log and return to systematic root-cause analysis
before any retry or tracked change.

- [ ] **Step 2: Verify all five final strict compiler boundaries**

Run:

```bash
ruby -rjson -rshellwords -e '
entries = JSON.parse(File.read(ARGV.fetch(0)))
common_ordinary = [
  "/home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl",
  "/home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl/build/ocl",
  "/home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl/build"
]
specs = {
  "deployer-opcua" => [
    "/bin/deployer.cpp",
    "CMakeFiles/deployer-opcua.dir/",
    common_ordinary + [
      "/home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl/build/bin"
    ]
  ],
  "ctaskbrowser-opcua" => [
    "/bin/ctaskbrowser-opcua.cpp",
    "CMakeFiles/ctaskbrowser-opcua.dir/",
    common_ordinary + [
      "/home/metanc/liufang/src/rock-orocos/toolchain/tools/ocl/build/bin"
    ]
  ],
  "orocos-ocl-deployment-opcua" => [
    "/deployment/OpcUaDeploymentComponent.cpp",
    "CMakeFiles/orocos-ocl-deployment-opcua.dir/",
    common_ordinary
  ],
  "ocl_opcua_deployment_test" => [
    "/deployment/tests/opcua_deployment_test.cpp",
    "CMakeFiles/ocl_opcua_deployment_test.dir/",
    common_ordinary
  ]
}
dependencies = [
  "/home/metanc/.orocos/toolchain/include/orocos",
  "/usr/xenomai/include/trank",
  "/usr/xenomai/include/cobalt",
  "/usr/xenomai/include",
  "/usr/xenomai/include/alchemy",
  "/home/metanc/.orocos/toolchain/include"
]
specs.each do |target, (suffix, marker, ordinary)|
  entry = entries.find do |item|
    item.fetch("file").end_with?(suffix) &&
      item.fetch("command").include?(marker)
  end
  abort "#{target} compile command is missing" unless entry
  tokens = Shellwords.split(entry.fetch("command"))
  %w[-std=c++20 -Wall -Wextra -Wpedantic -Werror].each do |flag|
    abort "#{target} missing required flag: #{flag}" unless tokens.include?(flag)
  end
  ordinary.each do |path|
    abort "#{target} OCL include is not ordinary: #{path}" unless tokens.include?("-I#{path}")
    system_pair = tokens.each_cons(2).any? { |a, b| a == "-isystem" && b == path }
    abort "#{target} OCL include became system: #{path}" if system_pair || tokens.include?("-isystem#{path}")
  end
  dependencies.each do |path|
    system_pair = tokens.each_cons(2).any? { |a, b| a == "-isystem" && b == path }
    abort "#{target} dependency is not system: #{path}" unless system_pair || tokens.include?("-isystem#{path}")
  end
end
puts "validated all four final OCL OPC UA C++20 warning and system-include boundaries"
' toolchain/tools/ocl/build/compile_commands.json
```

Then run:

```bash
ruby -rjson -rshellwords -e '
entries = JSON.parse(File.read(ARGV.fetch(0)))
entry = entries.find { |item| item.fetch("file").end_with?("/src/client_session.cpp") }
abort "client_session compile command is missing" unless entry
tokens = Shellwords.split(entry.fetch("command"))
%w[-std=c++20 -Wall -Wextra -Wpedantic -Werror].each do |flag|
  abort "rtt_opcua missing required flag: #{flag}" unless tokens.include?(flag)
end
own = "/home/metanc/liufang/src/rock-orocos/toolchain/tools/rtt_opcua/include"
abort "rtt_opcua project include is not ordinary" unless tokens.include?("-I#{own}")
system_own = tokens.each_cons(2).any? { |a, b| a == "-isystem" && b == own }
abort "rtt_opcua project include became system" if system_own || tokens.include?("-isystem#{own}")
dependencies = [
  "/home/metanc/.orocos/toolchain/include/orocos",
  "/usr/xenomai/include/trank",
  "/usr/xenomai/include/cobalt",
  "/usr/xenomai/include",
  "/usr/xenomai/include/alchemy"
]
dependencies.each do |path|
  system_pair = tokens.each_cons(2).any? { |a, b| a == "-isystem" && b == path }
  abort "rtt_opcua dependency is not system: #{path}" unless system_pair || tokens.include?("-isystem#{path}")
end
puts "validated final rtt_opcua C++20 warning and system-include boundary"
' toolchain/tools/rtt_opcua/build/compile_commands.json
```

Expected: all five target checks pass after the complete build, with strict
maintained-source flags and system dependency paths intact.

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
`orogen` and `typegen` resolve below `/home/metanc/.orocos`.

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
`ctaskbrowser-opcua-xenomai`, xenomai mqueue transport, OPC UA metadata,
`orogen`, and `typegen`.

- [ ] **Step 5: Verify source, patch, stash, and all selected refs**

Run:

```bash
git status --short --branch
git -C toolchain/tools/ocl status --short --branch
git -C toolchain/tools/ocl diff --check
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

Expected: root has no new tracked source change; OCL and `rtt_opcua` retain
only their approved uncommitted CMake changes; RTT retains exactly its two
approved uncommitted wakeup files and both stash OIDs; every selected package
HEAD matches the exact synchronized ref.

Do not run the parent rebuild's RTT regression suite or OPC UA loopback smoke
test in this task.
