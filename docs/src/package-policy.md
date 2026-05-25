# Package Policy

This page defines which packages belong in the first `orocos-rock` workspace.

## Selection Rule

The initial workspace should include only packages that are required to:

- build the Orocos runtime used by MetaNC
- build the generator stack used by MetaNC
- preserve deployer, OCL, and RTT scripting

Everything else starts excluded unless a concrete MetaNC need appears.

## Must Use

| Package | Why it is required | Source policy |
|---|---|---|
| `orocos_toolchain` | root toolchain integration | MetaNC-maintained fork |
| `rtt` | Orocos runtime | MetaNC-maintained fork |
| `ocl` | deployer and OCL compatibility | MetaNC-maintained fork |
| `log4cpp` | runtime dependency used by the stack | MetaNC-maintained fork |
| `orogen` | component and typekit generation | MetaNC-maintained fork |
| `typelib` | generator type support | MetaNC-maintained fork |
| `utilmm` | generator/runtime support | MetaNC-maintained fork |
| `utilrb` | autoproj and generator support | Upstream |
| `rtt_typelib` | RTT and Typelib bridge | MetaNC-maintained fork |
| `stdint_typekit` | fixed-width integer typekit | MetaNC-maintained fork |

## Good Candidates

| Package | Why it may help | Source policy |
|---|---|---|
| `rtt_geometry` | useful geometry helpers without changing the runtime model | Upstream |
| `base/cmake` | build helper layer if a package truly needs it | Upstream |
| selected plain C++ Rock libraries | only when they solve a concrete MetaNC problem | Prefer upstream |

## Avoid For Now

| Package Area | Why it is avoided initially |
|---|---|
| `syskit` | changes the operational model toward Rock orchestration |
| `roby` | not needed for MetaNC's current deployment model |
| `tools/orocos.rb` as runtime control plane | not needed if deployment stays on deployer plus `.ops` |
| Vizkit and GUI tooling | not required for the first toolchain goal |
| broad Rock package groups | increases maintenance and build time without solving the current blocker |

## Fork Policy

The default rule is:

- fork only packages that MetaNC actively patches
- use upstream for everything else

Initial fork set:

- `orocos_toolchain`
- `rtt`
- `ocl`
- `log4cpp`
- `orogen`
- `typelib`
- `utilmm`
- `rtt_typelib`
- `stdint_typekit`

Upstream by default:

- `rtt_geometry`
- `utilrb`

## Source Of Truth

Forked package policy should be documented here first and then encoded in the
workspace overrides.

MetaNC product repositories should not silently redefine third-party source
policy on their own.

## Review Rule

Before adding a new package, answer these questions:

1. Does MetaNC need it to build or run?
2. Does it preserve the Orocos deployment model?
3. Can upstream be used directly?
4. Does it create a new long-term maintenance burden?

If the answer to 1 is no, do not add it.
