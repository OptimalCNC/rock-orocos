# Windows MSVC Handoff

This document records the native Windows state validated on 2026-08-18. At
handoff time, the implementation is on the local
`feature/pixi-windows-build` worktree, remains uncommitted, and has not been
pushed.

## Outcome

The repository can build a native, 64-bit MSVC Orocos/Rock prefix with the
Orocos target name `win32`. The build covers:

- `farbot`, `rtlog-cpp`, RTT, and the required RTT plugins
- `open62541`, `open62541pp`, and `rtt_opcua`
- OCL deployer, RTT script runner, OPC UA deployer, and OPC UA TaskBrowser
- readline-backed TaskBrowser completion, history, and line editing
- `utilmm`, Typelib and its Ruby extension, and `rtt_typelib`
- `utilrb`, `metaruby`, OroGen, and `typegen`

The acceptance path imports a C++ header with CastXML, generates an OroGen
project, builds and installs its task library, typekit, Typelib transport, and
deployer, then loads and runs the generated deployer. A separate standalone
Typegen project is generated, regenerated from its recorded command line,
built, installed, and imported through the deployer.

## Where Pixi Is Required

| Use | Active Pixi environment | Notes |
|---|---:|---|
| Build or rebuild the prefix | Required | Pixi supplies the locked CMake, Ruby, CastXML, pkg-config, Git, and compiler environment. Visual Studio 2022 C++ Build Tools must also be installed. |
| Develop or generate components | Required | Enter `pixi shell --locked`, then dot-source `dev-env.ps1`. |
| Run installed RTT/OCL tools in this workspace | Not required | Dot-source `env.ps1`; it supplies the installed runtime and vcpkg DLL paths. |
| Copy the prefix to another machine as an application | Not supported yet | The environment scripts contain absolute workspace and vcpkg paths, and dependency DLLs are not all bundled into the prefix. |

Pixi is therefore the supported Windows build and development entrypoint. It
is not a runtime container or an application installer. The root Pixi
workspace intentionally declares only `win-64`; the existing Linux build
continues to use Autoproj through `tools/setup.sh`.

## Reproduce the Build

From a PowerShell session with the Visual Studio 2022 C++ tools available:

```powershell
pixi install --locked
pixi run windows-build
```

The task uses these disposable and installed locations:

- source and build state: `build/windows-msvc`
- vcpkg checkout and installed dependencies: `build/vcpkg`
- validated public prefix: `install/windows-msvc`
- runtime activation: `install/windows-msvc/env.ps1`
- development activation: `install/windows-msvc/dev-env.ps1`

For component development:

```powershell
pixi shell --locked
. .\install\windows-msvc\dev-env.ps1
orogen --version
typegen --help
```

For runtime-only use in a normal PowerShell session:

```powershell
. .\install\windows-msvc\env.ps1
deployer-opcua-win32.exe --check --no-consolelog
```

`tools/build-windows-msvc.ps1` accepts repository and ref parameters for each
maintenance fork. A local repository is fetched into the disposable source
tree; the original checkout is not modified.

## Validation Evidence

The complete `pixi run windows-build` acceptance passed twice consecutively
during initial implementation, including an idempotent rebuild. After this
review guarded the non-MSVC `utilmm` path and fixed already-integrated patch
detection, a fresh complete acceptance run also passed. Another complete run
passed after adding the standalone Typegen acceptance. The validated behavior
includes:

- all expected runtime, development, pkg-config, and CMake artifacts installed
- RTT, OCL, OPC UA, Typelib, and generated component libraries discoverable
- `deployer-win32.exe`, `rttscript-win32.exe`, and
  `deployer-opcua-win32.exe` check mode
- OPC UA service startup without the former missing-`RtString` failure
- TaskBrowser linked to `readline.dll`
- `rtt_typelib` marshalling smoke test
- standalone Typegen generation, regeneration, build, installation, and import
- generated task library, typekit, Typelib transport, and deployer execution
- locked Pixi environment installation and clean patch reapplication
- recognition of a Windows patch already integrated in its source branch

RTT does not define `RtString` on the Windows target because Win32 disables
the `OS_RT_MALLOC` facility that owns that type. `rtt_opcua` now registers
`RtString` only when `OS_RT_MALLOC` is available. Linux retains its existing
`RtString` registration.

The latest complete pass resolved these source revisions, plus the tracked
patches where they were not already integrated:

| Source | Revision |
|---|---|
| `farbot` | `09fd406eef4778511e85b569e3e75cad3d5cf608` |
| `rtlog-cpp` | `5842ca36c69ad4ba34321eda80891c832298f161` |
| RTT | `1c86ccc32cafecd91e35b9b56ba9e75423360e5f` |
| `open62541` | `45e4cd3ef6c79a8e503d37c9f5c89fefe90d99db` |
| `open62541pp` | `b1696768b26a12d0f40fdac5ec62ad78d25fa236` |
| `rtt_opcua` | `e335e8588d3489e485215f02a760dcdf9c6844b2` |
| OCL | `7716782f92c1c42f92a846a053db32e8dc7785fc` |
| `utilmm` | `9bab24d43a691137e2f1cd50c742cdd9482d3c86` |
| Typelib | `8998f8f24d58d0e450c3a6bf1cccc9552e184980` |
| `rtt_typelib` | `c5b345a22036019f8ec4ed176299bab3b80aae0a` |
| `utilrb` | `0028fac920eac5d5f9332c3a3438dcf4b7562953` |
| `metaruby` | `26d25770fdad163226b5aede3f8f9b8364d22f4c` |
| OroGen | `546b1990221a7ebc86e787ea15a2e322c7e19d08` |
| vcpkg | `c5a15727ee70fddf0296f0d8aafc3f58916fefac` |

`.github/workflows/windows-msvc.yml` runs this locked Pixi task on
`windows-2022`. Its YAML and local command path are validated, but the workflow
has not run on GitHub at handoff time because the work remains local and
unpushed.

## Console And OPC UA Notes

TaskBrowser tab completion and command history are enabled through vcpkg's
readline port. History defaults to `.tb_history` in the launch directory and
can be changed with `ORO_TB_HISTFILE`. In a native Windows console, use `quit`
or Ctrl+Z followed by Enter for end-of-input; Ctrl+D is not the Windows EOF
sequence.

A server may listen on `0.0.0.0`, but a client must connect to a concrete host
address. For a local UaExpert session, use `opc.tcp://127.0.0.1:4840` rather
than `opc.tcp://0.0.0.0:4840`.

## Patch Inventory

Windows source changes remain staged as patches under `tools/windows-patches`
and are applied only to disposable Windows checkouts:

| Patch | Purpose | Linux consideration before upstreaming |
|---|---|---|
| `rtt-msvc-cxx20.patch` | Modern C++ callable traits and MSVC/Win32 fixes | Shared RTT headers change; run the full Linux RTT test suite. |
| `rtt-opcua-msvc.patch` | MSVC object-model fix and conditional `RtString` registration | Linux keeps `RtString`; run Linux foundation and protocol tests. |
| `ocl-opcua-msvc.patch` | OPC UA linkage and MSVC readline discovery | Confirm normal Linux readline/editline detection and OCL tests. |
| `utilrb-windows.patch` | Portable path splitting and argv-based pkg-config calls | Changes are portable, but run the utilrb Ruby tests. |
| `utilmm-msvc.patch` | Windows plugins/demangling and vcpkg Boost discovery | Non-MSVC Boost discovery and test defaults are preserved; run Linux utilmm tests. |
| `typelib-msvc.patch` | Windows DLL/plugin loading, Ruby extension, paths, and install layout | Shared CMake and Ruby parsing change; run Typelib C++ and Ruby tests on Linux. |
| `orogen-msvc.patch` | Win32 target generation, paths, exports, install rules, modern standalone CMake, and safely quoted regeneration arguments | Linux defaults remain selected, but run Linux generation/build tests for all transports. |

Do not treat a successful Windows patch application as proof that a patch is
ready to merge into a maintenance fork. Each patch should be split into
focused commits and validated by that repository's Linux and Windows CI.

## Linux Isolation Review

The local branch currently points at the same commit as `main`; all Windows
work is in the working tree. No Linux shell script, Autoproj manifest or
override, Linux workflow, or Linux package source is modified. The executable
changes are PowerShell scripts, a Windows-only GitHub workflow, smoke fixtures,
and patch files consumed only by the Windows PowerShell build.

Apart from the new `win-64` Pixi files, the shared root changes are limited to
documentation, ignore rules, and line ending rules. `pixi.toml` is not
referenced by the Linux workflow. Under Ubuntu 22.04 in WSL, the following
checks passed after the Windows changes:

- Bash syntax for every `tools/*.sh` entrypoint
- repository, Autoproj, native CI, and package-test CI policy checks
- Autoproj launcher regression
- installed environment transaction regression
- workspace environment nounset regression
- workspace update regression
- patched `utilmm` configure and `libutilmm.so` build with GCC and Ubuntu's
  original Boost module discovery
- patched standalone Typegen CMake output configured and its core typekit
  target built with GCC against the installed Linux prefix

This establishes that the current root changes do not alter the working Linux
path. It does not replace Linux testing when the patch contents are eventually
merged into the individual source repositories. A complete patched Linux
Typegen generation was not run because the existing WSL prefix does not
provide `castxml`; full Linux generation and transport tests therefore remain
part of the OroGen maintenance-fork work.

## Known Gaps

- The installed prefix is not relocatable and is not an application package.
- vcpkg and most source refs use moving branches; Pixi dependencies are locked,
  but the entire source graph is not yet pinned to immutable commits.
- The `win32` target supports the Typelib transport. CORBA and mqueue are not
  part of the Windows contract.
- The Windows build currently disables most upstream unit-test suites and
  relies on the integrated acceptance checks.
- Visual Studio 2022 C++ Build Tools remain an external prerequisite.
- Readline is GPL-2.0; distributed TaskBrowser-linked binaries must use
  GPL-compatible terms.

Before publishing an application, pin all source revisions, copy required
runtime DLLs into a relocatable prefix, generate a clean-machine package, and
test install, activation, component loading, console editing, and OPC UA from
that package.
