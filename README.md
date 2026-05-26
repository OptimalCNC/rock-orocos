# orocos-rock

Standalone Orocos/Rock toolchain workspace for rebuilding the Orocos runtime and
generator stack on current Linux distributions.

Target CLI:

```bash
./tools/setup.sh --prefix ~/.orocos
```

This repository focuses on:

- package selection for a small Orocos/Rock toolchain
- source overrides to public maintenance branches
- fixes for newer Linux distributions and newer compilers
- reduced compile warnings and compatibility issues
- autoproj configuration
- OCL and RTT scripting enablement
- install and environment export policy

This repository does not own downstream application code, component models, or
deployment scripts. Downstream projects should consume only the installed
prefix and the generated environment scripts.

## Repository Boundary

```text
orocos-rock
  -> builds and installs Orocos/Rock toolchain dependencies
  -> exports runtime and development environments

downstream Orocos projects
  -> source the installed prefix
  -> build their own typekits, components, and deployment scripts
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
