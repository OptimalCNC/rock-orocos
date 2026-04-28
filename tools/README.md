# tools

This directory contains the small wrapper scripts that operate the workspace.

User entrypoint:

- `setup.sh`

Maintainer building blocks:

- `bootstrap.sh`
- `install.sh`
- `export-env.sh`
- `install-autoproj.sh`
- `validate-install.sh`
- `docker-build.sh`

These scripts should stay thin.

The source of truth for package policy belongs in tracked autoproj config and
repository documentation, not in ad hoc shell logic.
