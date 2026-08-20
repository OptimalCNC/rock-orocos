# orocos-rock

Standalone [Orocos](https://www.orocos.org/) / Rock toolchain workspace for
rebuilding RTT, OCL, `orogen`, `typegen`, and related generator support on
current Linux distributions and native Windows.

The repository keeps the scope narrow:

- maintain a small Autoproj package layout
- use public maintenance branches for compiler and distribution fixes
- reduce build warnings and compatibility issues from newer toolchains
- provide a native OPC UA RTT transport and remote deployer tools
- install one reusable prefix with runtime and development environment scripts

## Install

```bash
./tools/setup.sh --prefix ~/.orocos
```

The installed prefix exports:

- `env.sh` for runtime tools such as `deployer-gnulinux`
- `deployer-opcua` and `ctaskbrowser-opcua` for IPv4 LAN remote access
- `dev-env.sh` for generator tools such as `orogen` and `typegen`

RTT CORBA sources remain available in their upstream packages, but this
workspace configures CORBA off and does not install CORBA artifacts.

Downstream projects should consume the installed prefix, not the internal
Autoproj workspace.

## Windows Development

The native Windows path builds and validates both the RTT/OCL runtime and the
OroGen development stack. This includes `open62541`, `open62541pp`,
`rtt_opcua`, `utilmm`, Typelib and its Ruby extension, `rtt_typelib`, `utilrb`,
`metaruby`, `orogen`, and `typegen`. Its acceptance test generates, builds,
loads, and runs a small component, typekit, Typelib transport, and deployer
against the installed prefix. It separately uses `typegen` to generate,
regenerate, build, install, and import a standalone typekit and Typelib
transport.

Install Pixi and the Visual Studio 2022 C++ build tools, then create the locked
development environment and run the build:

```powershell
pixi install --locked
pixi run windows-build
```

Enter the Pixi environment and dot-source the generated runtime or development
environment. The development environment includes the runtime environment:

```powershell
pixi shell --locked
. .\install\windows-msvc\dev-env.ps1
orogen --version
typegen --help
deployer-opcua-win32.exe --check --no-consolelog
```

Use `env.ps1` instead when only the runtime is needed. OCL also installs
extensionless launcher scripts for POSIX-compatible shells. The generated
Windows environments currently record the vcpkg prefix because its runtime
DLLs have not yet been copied into the installed prefix. The Windows TaskBrowser
uses vcpkg's GPL-2.0 readline implementation for tab completion, line editing,
and command history. History is stored in `.tb_history` in the launch directory;
set `ORO_TB_HISTFILE` to override it. Use `quit`, or Ctrl+Z followed by Enter,
for end-of-input in a native Windows console.

The Windows generator defaults to the `typelib` transport. CORBA and mqueue
remain disabled for the `win32` target, so this is a native Windows development
contract rather than byte-for-byte feature parity with `gnulinux`.

During maintenance-fork development, point the same task at a local Git
checkout without changing tracked source policy:

```powershell
pixi run windows-build -- `
  -RttRepository D:\src\rtt `
  -RttRef my-windows-branch `
  -RttOpcuaRepository D:\src\rtt_opcua `
  -RttOpcuaRef my-windows-branch `
  -TypelibRepository D:\src\tools-typelib `
  -TypelibRef my-windows-branch `
  -OrogenRepository D:\src\tools-orogen `
  -OrogenRef my-windows-branch
```

The task writes disposable build state below `build/windows-msvc` and installs
the validated prefix and its `env.ps1`/`dev-env.ps1` entrypoints below
`install/windows-msvc`. Windows source fixes live on the selected maintenance
fork defaults. The remaining upstream-only `utilrb` fix is kept under
`tools/windows-patches` and applied to the disposable checkout.

## Windows Packages

The same locked source set can be built as two relocatable `win-64` Conda
packages. `orocos` contains the runtime, while `orocos-dev` contains headers,
build metadata, the bundled dependency SDK, OroGen, and Typegen. Build and test
both with:

```powershell
pixi install --locked -e package
pixi run --locked package-build
```

For a downstream Pixi workspace, add the public channel before adding the
development package:

```powershell
pixi workspace channel add https://prefix.dev/metanc/orocos
pixi workspace channel add conda-forge
pixi add orocos-dev==0.1.0
pixi shell
. "$env:CONDA_PREFIX\Library\dev-env.ps1"
```

The package recipe and local-channel validation workflow are documented in
[`packaging/README.md`](./packaging/README.md).

The OptimalCNC publication channel has three distinct forms:

- Upload: `metanc/orocos`
- Consumer: `https://prefix.dev/metanc/orocos`
- Website: `https://prefix.dev/channels/@metanc/orocos`

The `Windows Conda Packages` GitHub workflow builds and retains verified
packages for pull requests and `main`. A published, non-prerelease GitHub
Release in `OptimalCNC/rock-orocos` is the only publication trigger and uses
Prefix Repository Access through OIDC. The one-time channel setup and release
sequence are documented in the packaging guide.

## Documentation

- [User Guide](./docs/src/user-guide.md)
- [Maintainer Guide](./docs/src/maintainer-guide.md)
- [Windows MSVC Handoff](./docs/src/windows-msvc-handoff.md)
- [Architecture](./docs/src/architecture.md)
- [Package Policy](./docs/src/package-policy.md)
- [Install Contract](./docs/src/install-contract.md)
- [Native OPC UA Reference](./docs/src/opcua-reference.md)
- [Planned Work / TODO](./docs/src/todo/index.md)
