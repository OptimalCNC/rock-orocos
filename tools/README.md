# tools

This directory contains the small wrapper scripts that operate the workspace.

User entrypoints:

- `setup.sh`
- `update.sh` updates the root and configured Autoproj package sources without
  building or installing them
- `build-windows-msvc.ps1` builds and validates the native Windows RTT/OCL/OPC
  UA and OroGen development prefix; the `windows-build` Pixi task is the normal
  entrypoint

Maintainer building blocks:

- `bootstrap.sh`
- `install.sh`
- `export-env.sh`
- `export-windows-env.ps1` writes the installed Windows `env.ps1` and
  `dev-env.ps1` activation scripts
- `install-ruby-tools.ps1` installs the Windows Ruby generator gems into the
  public toolchain prefix
- `install-autoproj.sh`
- `validate-install.sh`
- `docker-build.sh`

Focused regression tests:

- `test-update.sh`
- `windows-generator-smoke/` is generated and compiled by the Windows Pixi
  build to exercise Typelib, OroGen, standalone Typegen regeneration, typekit,
  transport, and deployer support

These scripts should stay thin.

The source of truth for package policy belongs in tracked autoproj config and
repository documentation, not in ad hoc shell logic.
