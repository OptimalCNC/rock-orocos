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

The GNU/Linux build also keeps CORBA disabled. Native remote access is provided
by the OPC UA transport.

## Update Sources Without Building

To update this repository and every package selected by its Autoproj layout,
run this command from the repository root:

```bash
./tools/update.sh --prefix ~/.orocos --target gnulinux
```

The command first fast-forwards the current root branch from its configured
upstream, then updates the complete Autoproj-managed package layout. If the
root changes, the updated command re-executes itself once before package
sources are updated.

Tracked package policy remains authoritative: branch selections advance to
their configured branch tips, tag selections remain pinned, and the current
root variant selects the maintained `liufang-robot` or `OptimalCNC` forks.

This command updates sources only. It does not build, install, install OS
dependencies, reset local changes, or update Autoproj itself. The root must be
on a clean named branch with a configured upstream. Autoproj rejects unsafe
package updates using its normal checks.

> [!NOTE]
> The repositories are updated independently. If a later package fails, an
> earlier root or package fast-forward is not rolled back. Resolve the reported
> checkout and run the command again.

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
command -v deployer-opcua-gnulinux
command -v ctaskbrowser-opcua-gnulinux
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

## Use The OPC UA Deployer

Create a startup script that imports every required typekit before starting the
endpoint, then explicitly publishes each custom component:

```text
import("sample_typekit")
loadComponent("sample", "SampleComponent")
opcua.start()
opcua.publishComponent("sample")
```

Start the deployer with that script:

```bash
source ~/.orocos/env.sh
deployer-opcua site.ops
```

The default listener is `opc.tcp://0.0.0.0:4840/rtt` and accepts connections
on all IPv4 interfaces. Clients must use the server host's concrete LAN IPv4
address, for example `opc.tcp://192.0.2.10:4840/rtt`. In another sourced shell,
attach the remote TaskBrowser to the published deployer component:

```bash
ctaskbrowser-opcua opc.tcp://192.0.2.10:4840/rtt Deployer
```

Use `--opcua-port` or `--opcua-endpoint-path` when a different port or path is
needed. The listener address is not configurable from the CLI. The unsuffixed
commands dispatch to the executable for the selected `OROCOS_TARGET`.

> [!IMPORTANT]
> `deployer-opcua` constructs the local Deployer with its OPC UA listener
> stopped. Import typekits and their OPC UA transport plugins before
> `opcua.start()`: the first start freezes the process-wide datatype registry.
> `ctaskbrowser-opcua` cannot connect until start succeeds and the complete
> Deployer interface has been published.

`opcua.endpointUrl()` reports the configured URL even while stopped.
`opcua.isRunning()` becomes true only after the listener is running and the
Deployer publication is complete. Starting an already running endpoint and
publishing the same component instance again are successful no-ops.

Publication is strict and static. The complete supported RTT interface is
published, including nested services, operations, properties, attributes,
constants, and ports. One unsupported resource rejects the whole component and
leaves diagnostics available through `opcua.unsupportedResources(name)`.
Resources added after publication are not added to the endpoint.

`Server=true` does not publish a component through OPC UA. This version has no
unpublish operation, so a component that has been published cannot be unloaded
through the Deployer while the endpoint exists.

> [!WARNING]
> The remote deployer can load components and invoke exported operations.
> The current IPv4 LAN endpoint uses `SecurityPolicy None` and provides no
> authentication or authorization. Use it only on an isolated network and/or
> restrict access with host firewall rules.

## C++20 And Type Names

This toolchain requires C++20. RTT scripts and generated interfaces use the
canonical built-in names `Bool`, `Int8`, `UInt8`, `Int16`, `UInt16`, `Int32`,
`UInt32`, `Int64`, `UInt64`, `Float32`, `Float64`, `Char`, `String`, and `Void`.
Legacy script-visible names such as `int`, `short`, `double`, and `string` are
not registered.

RTT service requester code uses `requests()` because `requires` is a C++20
keyword. See [Native OPC UA Reference](./opcua-reference.md) for the current
datatype, publication, and transport contracts.

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
