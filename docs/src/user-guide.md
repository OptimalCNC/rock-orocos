# User Guide

This page is for a MetaNC developer who only needs to install and consume the
Orocos/Rock toolchain.

The normal local install prefix is:

```text
~/.orocos
```

> [!IMPORTANT]
> MetaNC should use the installed prefix. It should not depend on checkout paths
> inside the `orocos-rock` workspace.

## Install In Simple Steps

Run these commands from the `orocos-rock` repository root:

```bash
./tools/setup.sh --prefix ~/.orocos
```

`setup.sh` installs Autoproj if needed, prepares the workspace, builds and
installs the selected toolchain packages, and validates the installed prefix.

The setup may ask for `sudo` because Autoproj installs operating-system packages
declared by the selected Orocos/Rock packages.

## Use The Installed Toolchain

For MetaNC development, source the development environment before configuring or
building MetaNC:

```bash
source ~/.orocos/dev-env.sh
cmake --preset dev
cmake --build --preset dev
```

For runtime-only use, source:

```bash
source ~/.orocos/env.sh
```

## Validate Your Shell

After sourcing `dev-env.sh`, these commands should resolve:

```bash
command -v deployer-gnulinux
command -v orogen
command -v typegen
```

The printed paths should come from `~/.orocos` or from paths made available by
that prefix.

## Optional Shell Startup

If you want the runtime environment in every new shell, add this line to
`~/.bashrc`:

```bash
. "$HOME/.orocos/env.sh"
```

If you want every shell to include generator tools as well, use:

```bash
. "$HOME/.orocos/dev-env.sh"
```
