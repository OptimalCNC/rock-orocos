# orocos-rock

MetaNC-specific Orocos/Rock toolchain workspace.

Target CLI:

```bash
./tools/setup.sh --prefix ~/.orocos
```

This repository owns the third-party toolchain contract for MetaNC:

- package selection
- source overrides to maintained forks
- autoproj configuration
- OCL and RTT scripting enablement
- install and environment export policy

This repository does not own:

- MetaNC `Core`
- MetaNC Orocos packages such as `meta_nc_core_types` and `meta_nc_axis`
- MetaNC `.ops` deployment scripts
- MetaNC top-level CMake build and tests

## Repository Boundary

```text
orocos-rock
  -> builds and installs Orocos/Rock toolchain dependencies
  -> exports runtime and development environments

MetaNC
  -> builds MetaNC code against the installed toolchain
  -> owns CNC semantics, adapters, components, and deployment scripts
```

## Document Map

- [Book Summary](./docs/src/SUMMARY.md)
- [User Guide](./docs/src/user-guide.md)
- [Maintainer Guide](./docs/src/maintainer-guide.md)
- [Architecture](./docs/src/architecture.md)
- [Package Policy](./docs/src/package-policy.md)
- [Install Contract](./docs/src/install-contract.md)
- [Bootstrap Workflow](./docs/src/bootstrap-workflow.md)

## Initial Layout

```text
orocos-rock/
├── README.md
├── docs/
│   ├── book.toml
│   └── src/
│       ├── SUMMARY.md
│       ├── index.md
│       ├── user-guide.md
│       ├── maintainer-guide.md
│       ├── reference.md
│       ├── for-maintainers.md
│       ├── for-metanc-developers.md
│       ├── architecture.md
│       ├── bootstrap-workflow.md
│       ├── install-contract.md
│       └── package-policy.md
├── autoproj/
│   ├── README.md
│   ├── init.rb
│   ├── manifest
│   ├── overrides.rb
│   └── overrides.yml
├── docker/
│   └── orocos-rock/
│       └── Dockerfile
└── tools/
    ├── README.md
    ├── bootstrap.sh
    ├── common.sh
    ├── docker-build.sh
    ├── export-env.sh
    ├── install-autoproj.sh
    ├── install.sh
    ├── setup.sh
    └── validate-install.sh
```

The tracked files above describe the control plane of the workspace.

After bootstrap, autoproj-managed package checkouts and build artifacts will be
created under the workspace root. Those generated directories are workspace
state, not the source of truth for policy.

## Documentation Build

The book uses `mdbook-mermaid` to render Mermaid diagrams from fenced Markdown
blocks.

```bash
mdbook build docs
```

Install `mdbook-mermaid` before building the book locally:

```bash
cargo install mdbook-mermaid
```
