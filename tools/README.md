# tools

This directory contains the small wrapper scripts that operate the workspace.

User entrypoints:

- `setup.sh`
- `update.sh` updates the root and configured Autoproj package sources without
  building or installing them

Maintainer building blocks:

- `bootstrap.sh`
- `install.sh`
- `export-env.sh`
- `install-autoproj.sh`
- `validate-install.sh`
- `docker-build.sh`

Focused regression tests:

- `test-update.sh`

These scripts should stay thin.

The source of truth for package policy belongs in tracked autoproj config and
repository documentation, not in ad hoc shell logic.
