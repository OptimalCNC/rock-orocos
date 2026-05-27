# orocos-rock

`orocos-rock` builds and installs a standalone Orocos/Rock dependency stack for
current Linux distributions. It is a toolchain rebuild workspace, not an
application repository.

The output is one install prefix that downstream Orocos projects can use during
configure, build, test, and deployment workflows.

## Start Here

| Reader | Start with | What you get |
|---|---|---|
| Toolchain user | [User Guide](./user-guide.md) | Simple install and source commands |
| Toolchain maintainer | [Maintainer Guide](./maintainer-guide.md) | Script flow, install effects, and validation rules |

## What This Repository Produces

A successful install provides:

- Orocos RTT runtime tools
- OCL deployer support
- RTT scripting support
- generator tools such as `orogen` and `typegen`
- `env.sh` for runtime use
- `dev-env.sh` for downstream development

The normal host prefix is `~/.orocos`.

> [!IMPORTANT]
> Downstream projects should depend on the installed prefix, not on internal
> checkout paths inside this workspace.

## Maintenance Direction

The public maintenance branches in this workspace carry build fixes for newer
Linux distributions and newer compilers. Keep those fixes focused on the
Orocos/Rock toolchain itself: runtime buildability, generator usability, warning
cleanup, and install-prefix portability.

## Policy Reference

Use the [Reference](./reference.md) section when changing package selection,
fork policy, install contracts, or bootstrap behavior.
