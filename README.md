# orocos-rock

Standalone [Orocos](https://www.orocos.org/) / Rock toolchain workspace for
rebuilding RTT, OCL, `orogen`, `typegen`, and related generator support on
current Linux distributions.

The repository keeps the scope narrow:

- maintain a small Autoproj package layout
- use public maintenance branches for compiler and distribution fixes
- reduce build warnings and compatibility issues from newer toolchains
- install one reusable prefix with runtime and development environment scripts

## Install

```bash
./tools/setup.sh --prefix ~/.orocos
```

The installed prefix exports:

- `env.sh` for runtime tools such as `deployer-gnulinux`
- `dev-env.sh` for generator tools such as `orogen` and `typegen`

Downstream projects should consume the installed prefix, not the internal
Autoproj workspace.

## Documentation

- [User Guide](./docs/src/user-guide.md)
- [Maintainer Guide](./docs/src/maintainer-guide.md)
- [Architecture](./docs/src/architecture.md)
- [Package Policy](./docs/src/package-policy.md)
- [Install Contract](./docs/src/install-contract.md)
