# Install Contract

This page defines the contract that `orocos-rock` exports to downstream Orocos
users.

## Output Model

`orocos-rock` should install to one prefix.

Recommended default:

```text
~/.orocos
```

The exact prefix may be configurable later, but the contract should stay the
same regardless of location.

## Required Outputs

The installed prefix must provide:

- Orocos runtime tools
- OCL deployer support
- RTT scripting support
- generator tools needed for typekit and component development
- environment setup for runtime use
- environment setup for development use

The selected Orocos target is part of the prefix contract. The default target
is `gnulinux`; a Xenomai build must be requested explicitly with
`--target xenomai`. The default prefix remains `~/.orocos` unless the caller
passes a different `--prefix`.

## Environment Scripts

### `env.sh`

Runtime-oriented environment.

It should make a shell ready for:

- the selected target deployer, such as `deployer-gnulinux` or
  `deployer-xenomai`
- Orocos component and plugin discovery
- running existing `.ops` scripts

It should not require source-tree state from this workspace or any downstream
project to be useful.

### `dev-env.sh`

Development-oriented environment.

It should extend the runtime environment with the extra tooling needed for:

- `orogen`
- `typegen`
- Typelib-related generators
- configuring and building downstream Orocos packages

This is the script downstream projects should source before configuring their
Orocos-facing packages.

`dev-env.sh` is also responsible for making the Ruby-based generator stack
usable from the installed prefix. Downstream users should expect the sourced
shell to find `orogen`, `typegen`, and their Ruby dependencies without any
access to the internal autoproj workspace.

## Downstream Assumptions

Downstream projects may assume that, after sourcing `dev-env.sh`, the shell can:

- find RTT and OCL build dependencies
- generate new typekits
- configure CMake packages that use Orocos macros
- build downstream Orocos packages against the installed toolchain
- resolve the Ruby gems needed by `orogen` and related generators

Downstream projects should not assume:

- direct access to the internal autoproj workspace layout
- specific checkout paths of third-party packages
- direct modification of the toolchain workspace during normal product builds
- a particular installed gem directory layout under the prefix

## Prefix Stability Rule

The install prefix is the public contract.

The internal autoproj workspace is not.

That means:

- the prefix layout should change rarely
- `OROCOS_PREFIX` is the public environment variable for the installed prefix
- `env.sh` and `dev-env.sh` should remain the stable entrypoints
- downstream builds should avoid depending on workspace-internal paths

The same rule applies to Ruby tooling: downstream users may rely on the
presence of generator commands after sourcing `dev-env.sh`, but should not
depend on how gems are staged inside the prefix.

`env.sh` exports the selected target through `OROCOS_TARGET`. Downstream
projects should treat this as a property of the installed prefix, not as a
workspace-internal setting.

## Development Environment Guarantees

After sourcing `dev-env.sh`, the shell must be usable as a standalone toolchain
environment. At minimum, the script must:

- prepend the installed toolchain executables to `PATH`
- expose the installed prefix through `CMAKE_PREFIX_PATH`
- expose pkg-config metadata through `PKG_CONFIG_PATH`
- expose Orocos plugin discovery paths for runtime tools
- expose the installed Ruby generator stack through `GEM_HOME`, `GEM_PATH`, or
  equivalent `RUBYLIB` setup
- expose CMake config packages for installed internal toolchain dependencies,
  including `farbot` and `rtlog-cpp`, so downstream configure checks can use
  the same prefix contract

Those variables are part of the behavior contract of `dev-env.sh`, even if the
exact internal directory layout changes later.

## Validation Expectations

An install is considered minimally valid when it can:

1. source `env.sh`
2. run the deployer for the selected target
3. source `dev-env.sh`
4. run `orogen`
5. run `typegen`
6. support a downstream Orocos configure step

## Relationship To Downstream Projects

Downstream projects should consume `orocos-rock` exactly like a third-party
dependency prefix.
