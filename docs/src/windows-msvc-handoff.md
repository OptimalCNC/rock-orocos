# Windows MSVC Handoff

This document records the native Windows state validated through 2026-08-19. The
organization-owned source fixes are integrated into the selected maintenance
fork defaults in both `liufang-robot` and `OptimalCNC`. The remaining
upstream-only `utilrb` fix is applied from the root workspace.

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
| Install the relocatable SDK | Required | Add `orocos-dev` to a downstream Pixi workspace, then dot-source `$env:CONDA_PREFIX\Library\dev-env.ps1`. |
| Install the relocatable runtime | Required for installation | Add `orocos`; its installed `env.ps1` uses only package-relative paths. |

Pixi is therefore the supported Windows build and development entrypoint. It
also installs the packaged runtime and SDK into downstream environments. The
root Pixi workspace intentionally declares only `win-64`; the existing Linux
build continues to use Autoproj through `tools/setup.sh`.

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

For a reproducible release-candidate build, use the complete source lock:

```powershell
pixi run --locked windows-build -- `
  -SourceLockPath packaging/source-lock.json
```

The lock mode rejects repository/ref overrides and verifies that every
checkout's final `HEAD` is the requested full commit. Omit the source lock for
ordinary development or integration testing against moving branch refs.

## Build The Packages

The package build uses the same source lock and produces two relocatable
`win-64` artifacts:

- `orocos` contains runtime executables, DLLs, plugins, typekits, OPC UA, and
  `env.ps1`.
- `orocos-dev` contains headers, import libraries, CMake/pkg-config metadata,
  the bundled dependency SDK, OroGen, Typegen, and `dev-env.ps1`. It requires
  the exact matching `orocos` build.

Build and test both from the repository root:

```powershell
pixi install --locked -e package
pixi run --locked package-render
pixi run --locked package-build
```

The 2026-08-19 local release-candidate build produced and tested
`orocos-0.1.0-h9490d1a_0.conda` and
`orocos-dev-0.1.0-h04e904a_0.conda`. Rattler Build tested each package in an
isolated environment. The development test generated and compiled fresh
OroGen and Typegen projects. Separate clean runtime and development Pixi
workspaces then installed from the local `file://` channel: the runtime check
ran the RTT/OCL/OPC UA tools without development files, while the development
check generated and compiled both downstream projects again.

`package-build` force-reindexes the local channel after its native tests pass.
This is required during local iteration because rebuilding an unchanged
version and build number replaces the artifact filename.

After publication, a downstream workspace consumes the packages with:

```powershell
pixi workspace channel add https://prefix.dev/liufang-robot/orocos
pixi workspace channel add conda-forge
pixi add orocos-dev==0.1.0
pixi shell
. "$env:CONDA_PREFIX\Library\dev-env.ps1"
```

Package construction and local-channel checks are detailed in
`packaging/README.md`. Upload is a separate release action and was not part of
the local validation recorded here.

## Package CI And Release

`.github/workflows/windows-packages.yml` now encodes the release path. Pull
requests, `main` pushes, and manual dispatches build the source-locked packages,
stage only the two verified `.conda` artifacts, record their checksums and
source lock, and install both exact builds through a fresh local-channel Pixi
cache. No event other than a published, non-prerelease GitHub Release can enter
the upload job.

The upload job has two additional boundaries:

- `github.repository` must be `liufang-robot/rock-orocos`, so the
  `OptimalCNC/rock-orocos` mirror cannot publish duplicate filenames; and
- only that job receives `id-token: write`, allowing Prefix Repository Access
  to authenticate it without a stored API key.

Before the first release, register `liufang-robot/rock-orocos` and the exact
workflow filename `windows-packages.yml` in the `liufang-robot/orocos` channel's
Repository Access settings. Grant package upload access without delete or
lifecycle permissions. Then let the package workflow pass on `main` and publish
release tag `v0.1.0` from the same commit. The job verifies the tag against the
package metadata, uploads both manifest-selected artifacts without overwrite
flags, and retries clean runtime and development installs through
`https://prefix.dev/liufang-robot/orocos` while the remote index becomes
visible.

The workflow and Repository Access mapping have not yet run on GitHub. The
2026-08-19 result remains a local release-candidate validation, not a record of
remote publication.

The packaged text configuration, environment scripts, CMake metadata, and
pkg-config metadata contain no workspace, temporary-build, or vcpkg-checkout
paths. Some MSVC and cached vcpkg binaries retain non-functional source/PDB
path strings. Those debug records do not participate in runtime lookup or
downstream build discovery and are not a relocation dependency.

## Validation Evidence

The complete `pixi run windows-build` acceptance passed twice consecutively
during initial implementation, including an idempotent rebuild. After this
review guarded the non-MSVC `utilmm` path and fixed already-integrated patch
detection, a fresh complete acceptance run also passed. Another complete run
passed after adding the standalone Typegen acceptance. A complete run against
the integrated maintenance-fork commits also passed. After adding the source
lock, two complete locked runs passed; the second also refreshed vcpkg's
untracked executable from the pinned commit's tool metadata. The validated
behavior includes:

- all expected runtime, development, pkg-config, and CMake artifacts installed
- RTT, OCL, OPC UA, Typelib, and generated component libraries discoverable
- `deployer-win32.exe`, `rttscript-win32.exe`, and
  `deployer-opcua-win32.exe` check mode
- OPC UA service startup without the former missing-`RtString` failure
- TaskBrowser linked to `readline.dll`
- `rtt_typelib` marshalling smoke test
- standalone Typegen generation, regeneration, build, installation, and import
- generated task library, typekit, Typelib transport, and deployer execution
- locked Pixi environment installation and clean remaining-patch application
- recognition of the integrated Windows changes in maintenance-fork sources

RTT does not define `RtString` on the Windows target because Win32 disables
the `OS_RT_MALLOC` facility that owns that type. `rtt_opcua` now registers
`RtString` only when `OS_RT_MALLOC` is available. Linux retains its existing
`RtString` registration.

The latest complete pass resolved these source revisions. They are encoded in
`packaging/source-lock.json`; the build also applies the remaining tracked
`utilrb` patch:

| Source | Revision |
|---|---|
| `farbot` | `09fd406eef4778511e85b569e3e75cad3d5cf608` |
| `rtlog-cpp` | `5842ca36c69ad4ba34321eda80891c832298f161` |
| RTT | `14e237f2c49fa2830f055b71b09f6921c3a07bee` |
| `open62541` | `45e4cd3ef6c79a8e503d37c9f5c89fefe90d99db` |
| `open62541pp` | `b1696768b26a12d0f40fdac5ec62ad78d25fa236` |
| `rtt_opcua` | `847669186f79dc206313e0f200604581d7031ad8` |
| OCL | `b80710cd9ba3c1172e355c351d79e6dab016e214` |
| `utilmm` | `fa212d0d232cf6d841edf9e9d4c43a26d223fedd` |
| Typelib | `20cb127d44dc33f91a67a4c7d7cba7b20e2379eb` |
| `rtt_typelib` | `c5b345a22036019f8ec4ed176299bab3b80aae0a` |
| `utilrb` | `0028fac920eac5d5f9332c3a3438dcf4b7562953` |
| `metaruby` | `26d25770fdad163226b5aede3f8f9b8364d22f4c` |
| OroGen | `dfa81b727f002dafb2f9b6b82e3205d375c77a66` |
| vcpkg | `c5a15727ee70fddf0296f0d8aafc3f58916fefac` |

`.github/workflows/windows-msvc.yml` runs on `windows-2022`, installs the
locked Pixi dependency graph, validates the source-lock contract, and builds
the requested integration refs. Release reproduction separately passes
`-SourceLockPath` as shown above.

## Console And OPC UA Notes

TaskBrowser tab completion and command history are enabled through vcpkg's
readline port. History defaults to `.tb_history` in the launch directory and
can be changed with `ORO_TB_HISTFILE`. In a native Windows console, use `quit`
or Ctrl+Z followed by Enter for end-of-input; Ctrl+D is not the Windows EOF
sequence.

A server may listen on `0.0.0.0`, but a client must connect to a concrete host
address. For a local UaExpert session, use `opc.tcp://127.0.0.1:4840` rather
than `opc.tcp://0.0.0.0:4840`.

## Source Integration

The RTT, `rtt_opcua`, OCL, `utilmm`, Typelib, and OroGen Windows changes are
integrated into their default `dev` branches. Both organizations point those
defaults at the same commits listed above. The complete Windows acceptance
passed against those integrated commits.

`tools/windows-patches/utilrb-windows.patch` is the only remaining patch. The
workspace consumes `rock-core/tools-utilrb` directly, and neither organization
has a maintained `tools-utilrb` fork. The patch keeps path splitting and
pkg-config invocation portable and is applied only to the disposable Windows
checkout.

## Linux Isolation Review

No Linux shell script, Autoproj manifest or override, Linux workflow, or Linux
package source is modified by the root Windows integration. The executable
root changes are PowerShell scripts, a Windows-only GitHub workflow, smoke
fixtures, and the remaining `utilrb` patch consumed only by the Windows build.

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
path. These focused checks do not replace each maintenance repository's full
Linux CI. A complete patched Linux Typegen generation was not run because the
existing WSL prefix does not provide `castxml`; full Linux generation and
transport tests therefore remain follow-up OroGen maintenance work.

## Known Gaps

- The direct `windows-build` workspace prefix is not relocatable. Use the
  `orocos` and `orocos-dev` packages when the installation must move between
  machines or prefixes.
- Ordinary development builds still default to moving integration refs. The
  package recipe uses `packaging/source-lock.json` and rejects moving refs.
- The `win32` target supports the Typelib transport. CORBA and mqueue are not
  part of the Windows contract.
- The Windows build currently disables most upstream unit-test suites and
  relies on the integrated acceptance checks.
- Visual Studio 2022 C++ Build Tools remain an external prerequisite.
- Readline is GPL-2.0; distributed TaskBrowser-linked binaries must use
  GPL-compatible terms.

Before publishing, review the bundled licenses and the GitHub release bundle.
Increase the recipe build number if an already-published filename must be
corrected. Never replace an existing channel artifact with `--force` or mask a
different-byte collision with `--skip-existing`.
