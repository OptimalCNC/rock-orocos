# Package Policy

This page defines which packages belong in the first `orocos-rock` workspace.

## Selection Rule

The initial workspace should include only packages that are required to:

- build the Orocos RTT runtime
- build the OCL deployer and scripting support
- build the generator stack used for typekits and components
- preserve deployer, OCL, and RTT scripting on current Linux distributions

Everything else starts excluded unless a concrete toolchain need appears.

## Must Use

| Package | Why it is required | Source policy |
|---|---|---|
| `orocos_toolchain` | root toolchain integration | Public maintenance fork when needed |
| `rtt` | Orocos runtime | Public maintenance fork |
| `ocl` | deployer and OCL compatibility | Public maintenance fork |
| `log4cpp` | runtime dependency used by the stack | Public maintenance fork |
| `orogen` | component and typekit generation | Public maintenance fork while generator fixes are needed |
| `typelib` | generator type support | Upstream |
| `utilmm` | generator/runtime support | Upstream |
| `utilrb` | autoproj and generator support | Upstream |
| `rtt_typelib` | RTT and Typelib bridge | Upstream |
| `stdint_typekit` | likely needed for fixed-width types | Upstream |

## Good Candidates

| Package | Why it may help | Source policy |
|---|---|---|
| `rtt_geometry` | useful geometry helpers without changing the runtime model | Upstream |
| `base/cmake` | build helper layer if a package truly needs it | Upstream |
| selected plain C++ Rock libraries | only when they solve a concrete toolchain problem | Prefer upstream |

## Avoid For Now

| Package Area | Why it is avoided initially |
|---|---|
| `syskit` | changes the operational model toward Rock orchestration |
| `roby` | not needed for the focused RTT/OCL/generator rebuild goal |
| `tools/orocos.rb` as runtime control plane | not needed if deployment stays on deployer plus `.ops` |
| Vizkit and GUI tooling | not required for the first toolchain goal |
| broad Rock package groups | increases maintenance and build time without solving the current blocker |

## Fork Policy

The default rule is:

- fork only packages that need current Linux or compiler compatibility fixes
- keep those changes on public `dev` branches
- use upstream for everything else

Initial public maintenance fork set:

- `rtt`
- `ocl`
- `log4cpp`
- `orogen`

Forks should carry focused portability work:

- newer compiler warning cleanup
- build-system fixes
- dependency discovery fixes
- distribution compatibility patches

Upstream by default:

- `rtt_geometry`
- `typelib`
- `utilmm`
- `utilrb`
- `rtt_typelib`
- `stdint_typekit`

## Source Of Truth

Forked package policy should be documented here first and then encoded in the
workspace overrides.

Downstream repositories should not silently redefine third-party source policy
on their own.

## Review Rule

Before adding a new package, answer these questions:

1. Does the focused RTT/OCL/generator toolchain need it to build or run?
2. Does it preserve the Orocos deployment model?
3. Can upstream be used directly?
4. Does it create a new long-term maintenance burden?

If the answer to 1 is no, do not add it.
