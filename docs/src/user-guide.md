# User Guide

This page is for users who need to install and consume the Orocos/Rock
toolchain.

The normal local install prefix is:

```text
~/.orocos
```

> [!IMPORTANT]
> Downstream projects should use the installed prefix. They should not depend
> on checkout paths inside the `orocos-rock` workspace.

## Install In Simple Steps

Run these commands from the `orocos-rock` repository root:

```bash
./tools/setup.sh --prefix ~/.orocos
```

`setup.sh` installs Autoproj if needed, prepares the workspace, builds and
installs the selected toolchain packages, and validates the installed prefix.

The setup may ask for `sudo` because Autoproj installs operating-system packages
declared by the selected Orocos/Rock packages.

The default target is `gnulinux`. To build a Xenomai-capable toolchain on a
host that already has Xenomai 3 development headers and libraries installed,
select the target explicitly:

```bash
export XENOMAI_DIR=/usr/xenomai
export XENOMAI_ROOT_DIR=/usr/xenomai
export PATH="$XENOMAI_DIR/bin:$PATH"

./tools/setup.sh --prefix ~/.orocos --target xenomai
```

The generated `~/.orocos/env.sh` then exports `OROCOS_TARGET=xenomai` by
default. A later `--target gnulinux` install to the same prefix switches the
prefix back to `OROCOS_TARGET=gnulinux`.

The Xenomai 3 build disables RTT CORBA by default, so OmniORB is not required.
If you are testing local uncommitted RTT or OCL Xenomai patches, use the
no-update maintainer workflow in
[Xenomai 3 Integration](./xenomai3-integration.md) instead of `setup.sh`.

## Use The Installed Toolchain

For development, source the development environment before configuring or
building downstream Orocos packages:

```bash
source ~/.orocos/dev-env.sh
cmake -S . -B build
cmake --build build
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

For a Xenomai install, validate `deployer-xenomai` instead:

```bash
source ~/.orocos/env.sh
echo "$OROCOS_TARGET"
command -v deployer-xenomai
deployer-xenomai --version
```

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
