# orocos-rock

`orocos-rock` builds and installs the Orocos/Rock dependency stack used by
MetaNC. It owns the third-party toolchain contract, not MetaNC product code.

The output is one install prefix that MetaNC can consume during configure,
build, test, and deployment workflows.

## Start Here

| Reader | Start with | What you get |
|---|---|---|
| MetaNC developer | [User Guide](./user-guide.md) | Simple install and source commands |
| Toolchain maintainer | [Maintainer Guide](./maintainer-guide.md) | Script flow, install effects, and validation rules |

## What This Repository Produces

A successful install provides:

- Orocos RTT runtime tools
- OCL deployer support
- RTT scripting support
- generator tools such as `orogen` and `typegen`
- `env.sh` for runtime use
- `dev-env.sh` for downstream MetaNC development

The normal host prefix is `~/.orocos`.

> [!IMPORTANT]
> MetaNC should depend on the installed prefix, not on internal checkout paths
> inside this workspace.

## Policy Reference

Use the [Reference](./reference.md) section when changing package selection,
fork policy, install contracts, or bootstrap behavior.
