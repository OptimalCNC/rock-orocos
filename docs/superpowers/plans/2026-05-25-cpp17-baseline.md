# C++17 Baseline Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the maintained Orocos/Rock toolchain explicitly build as C++17 without widening API changes beyond what the clean Ubuntu 22.04/24.04 CI gate can validate.

**Architecture:** Apply C++17 per package, starting with packages that already build cleanly or only need local CMake policy changes. Keep ABI-sensitive ownership/API migrations, especially `log4cpp` `std::auto_ptr`, in separate commits so failures are attributable.

**Tech Stack:** CMake, Autoproj, GCC on Ubuntu 22.04/24.04, GitHub Actions native matrix, Orocos RTT/OCL/Typelib/utilmm/log4cpp/orogen forks.

---

## File Structure

- Modify package build files in their package repos:
  - `toolchain/tools/typelib/CMakeLists.txt`
  - `toolchain/tools/utilmm/CMakeLists.txt`
  - `toolchain/tools/rtt/CMakeLists.txt`
  - `toolchain/tools/ocl/CMakeLists.txt`
  - `toolchain/tools/log4cpp/CMakeLists.txt`
  - `toolchain/tools/rtt_typelib/CMakeLists.txt`
  - `toolchain/stdint_typekit/CMakeLists.txt`
- Modify orogen generator defaults only after deciding generated typekits should default to C++17:
  - `toolchain/tools/orogen/lib/orogen/gen/project.rb`
  - `toolchain/tools/orogen/lib/orogen/gen/typekit.rb`
  - `toolchain/tools/orogen/lib/orogen/templates/typekit/*.cmake`
- Track policy and gates in the manager repo:
  - `docs/src/modernization-plan.md`
  - `tools/check-native-ci.rb`

## Chunk 1: Low-Risk C++17 Declarations

### Task 1: Bump Typelib From C++11 To C++17

**Files:**
- Modify: `toolchain/tools/typelib/CMakeLists.txt`

- [x] **Step 1: Edit the standard declaration**

Change:

```cmake
#required because of the use of std::unique_ptr
set (CMAKE_CXX_STANDARD 11)
```

to:

```cmake
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
```

- [x] **Step 2: Build Typelib locally**

Run:

```bash
./tools/install.sh --prefix ~/.orocos -- typelib rtt_typelib stdint_typekit
```

Expected: command exits 0.

- [x] **Step 3: Check warning budget**

Run:

```bash
rg -n "warning:|deprecated|pragma message" ~/.orocos/toolchain/log/typelib-build.log ~/.orocos/toolchain/log/rtt_typelib-build.log ~/.orocos/toolchain/log/stdint_typekit-build.log || true
```

Expected: no matches.

- [x] **Step 4: Commit in `tools-typelib`**

```bash
git -C toolchain/tools/typelib add CMakeLists.txt
git -C toolchain/tools/typelib commit -m "Build Typelib as C++17"
```

### Task 2: Add Explicit C++17 To Utilmm

**Files:**
- Modify: `toolchain/tools/utilmm/CMakeLists.txt`

- [x] **Step 1: Add standard declaration after `project(Util--)`**

```cmake
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
```

- [x] **Step 2: Build utilmm locally**

Run:

```bash
./tools/install.sh --prefix ~/.orocos -- utilmm
```

Expected: command exits 0.

- [x] **Step 3: Check warning budget**

Run:

```bash
rg -n "warning:|deprecated|pragma message" ~/.orocos/toolchain/log/utilmm-build.log || true
```

Expected: no matches.

- [x] **Step 4: Commit in `utilmm`**

```bash
git -C toolchain/tools/utilmm add CMakeLists.txt
git -C toolchain/tools/utilmm commit -m "Build utilmm as C++17"
```

## Chunk 2: Runtime Packages

### Task 3: Add Explicit C++17 To RTT

**Files:**
- Modify: `toolchain/tools/rtt/CMakeLists.txt`

- [x] **Step 1: Add standard declaration after `PROJECT(orocos-rtt)`**

```cmake
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
```

- [x] **Step 2: Build RTT and dependent bridges locally**

Run:

```bash
./tools/install.sh --prefix ~/.orocos -- rtt rtt_typelib stdint_typekit
```

Expected: command exits 0.

- [x] **Step 3: Check warning budget**

Run:

```bash
rg -n "warning:|deprecated|pragma message" ~/.orocos/toolchain/log/rtt-build.log ~/.orocos/toolchain/log/rtt_typelib-build.log ~/.orocos/toolchain/log/stdint_typekit-build.log || true
```

Expected: no matches.

- [x] **Step 4: Commit in `rtt`**

```bash
git -C toolchain/tools/rtt add CMakeLists.txt
git -C toolchain/tools/rtt commit -m "Build RTT as C++17"
```

### Task 4: Add Explicit C++17 To OCL

**Files:**
- Modify: `toolchain/tools/ocl/CMakeLists.txt`

- [x] **Step 1: Add standard declaration after `PROJECT(ocl)`**

```cmake
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
```

- [x] **Step 2: Build OCL locally**

Run:

```bash
./tools/install.sh --prefix ~/.orocos -- ocl
```

Expected: command exits 0.

- [x] **Step 3: Check warning budget**

Run:

```bash
rg -n "warning:|deprecated|pragma message" ~/.orocos/toolchain/log/ocl-build.log || true
```

Expected: no matches.

- [x] **Step 4: Commit in `ocl`**

```bash
git -C toolchain/tools/ocl add CMakeLists.txt
git -C toolchain/tools/ocl commit -m "Build OCL as C++17"
```

## Chunk 3: Compatibility Blockers

### Task 5: Modernize log4cpp Ownership Before C++17

**Files:**
- Modify: `toolchain/tools/log4cpp/include/log4cpp/*Factory.hh`
- Modify: `toolchain/tools/log4cpp/include/log4cpp/BufferingAppender.hh`
- Modify: `toolchain/tools/log4cpp/src/*Factory.cpp`
- Modify: log4cpp appender/layout factory source files that return `std::auto_ptr`

- [ ] **Step 1: Audit public `std::auto_ptr` usage**

Run:

```bash
rg -n "std::auto_ptr" toolchain/tools/log4cpp/include toolchain/tools/log4cpp/src
```

Expected: current ownership API locations are listed.

- [ ] **Step 2: Decide compatibility policy**

Use `std::unique_ptr` internally. For public API, either:

- switch directly to `std::unique_ptr` if downstream API break is acceptable, or
- add a package-local ownership typedef as a compatibility shim and migrate call sites first.

Do not mix both approaches in one commit.

- [ ] **Step 3: Build log4cpp locally**

Run:

```bash
./tools/install.sh --prefix ~/.orocos -- log4cpp
```

Expected: command exits 0.

- [ ] **Step 4: Add C++17 standard declaration**

Modify `toolchain/tools/log4cpp/CMakeLists.txt` after `PROJECT ( LOG4CPP )`:

```cmake
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
```

- [ ] **Step 5: Rebuild and check warning budget**

Run:

```bash
./tools/install.sh --prefix ~/.orocos -- log4cpp
rg -n "warning:|deprecated|pragma message" ~/.orocos/toolchain/log/log4cpp-build.log || true
```

Expected: no matches.

- [ ] **Step 6: Commit in `log4cpp`**

```bash
git -C toolchain/tools/log4cpp add CMakeLists.txt include src
git -C toolchain/tools/log4cpp commit -m "Build log4cpp as C++17"
```

## Chunk 4: Generated Typekits And Manager Gate

### Task 6: Set Generated Typekit C++17 Policy In orogen

**Files:**
- Inspect: `toolchain/tools/orogen/lib/orogen/gen/project.rb`
- Inspect: `toolchain/tools/orogen/lib/orogen/gen/typekit.rb`
- Modify only if needed after inspection.

- [ ] **Step 1: Confirm current default behavior**

Run:

```bash
rg -n "cxx_standard|@cxx_standard|dsl_attribute :cxx_standard" toolchain/tools/orogen/lib/orogen/gen
```

Expected: identify whether projects default to no explicit standard.

- [ ] **Step 2: Add default only if no explicit standard is set**

If the generator currently leaves `cxx_standard` nil, set the MetaNC-maintained default to `c++17` while preserving explicit `.orogen` values.

- [ ] **Step 3: Build orogen locally**

Run:

```bash
./tools/install.sh --prefix ~/.orocos -- orogen
```

Expected: command exits 0.

- [ ] **Step 4: Commit in `tools-orogen`**

```bash
git -C toolchain/tools/orogen add lib/orogen
git -C toolchain/tools/orogen commit -m "Default generated typekits to C++17"
```

### Task 7: Add Manager-Level C++17 Policy Check

**Files:**
- Modify or create: `tools/check-cpp17-policy.rb`
- Modify: `tools/check-autoproj-policy.rb`
- Modify: `docs/src/modernization-plan.md`

- [ ] **Step 1: Create a policy check**

The check should verify maintained package build files contain:

```text
CMAKE_CXX_STANDARD 17
CMAKE_CXX_STANDARD_REQUIRED ON
```

for packages where the C++17 migration is complete.

- [ ] **Step 2: Wire it into existing checks**

Add `tools/check-cpp17-policy.rb` existence to `tools/check-autoproj-policy.rb`.

- [ ] **Step 3: Run local manager checks**

Run:

```bash
ruby tools/check-cpp17-policy.rb
ruby tools/check-autoproj-policy.rb
ruby tools/check-native-ci.rb
ruby tools/check-clean-room-docker.rb
```

Expected: all exit 0.

- [ ] **Step 4: Open a PR for manager changes**

Follow PR-only workflow:

```bash
git checkout -b policy/cpp17-baseline
git add docs/src/modernization-plan.md tools/check-cpp17-policy.rb tools/check-autoproj-policy.rb
git commit -m "Track C++17 package policy"
git push -u origin policy/cpp17-baseline
gh pr create --base main --head policy/cpp17-baseline
```

## Final Verification

- [ ] Push package fork branches after each package commit.
- [ ] Trigger or update the manager PR after package fork tips are pushed.
- [ ] Wait for GitHub Actions `Native Toolchain Matrix` to pass on Ubuntu 22.04 and 24.04.
- [ ] Confirm warning budget passes in both jobs.
- [ ] Merge the manager PR only after CI is green.
