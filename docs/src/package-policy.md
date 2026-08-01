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
| `farbot` | lock-free queue dependency for the future RT-safe logger core | Public maintenance fork while install/export rules are needed |
| `rtlog-cpp` | RT-safe logging queue and bounded formatting implementation for the RTT logger core | Public maintenance fork while install/export rules are needed |
| `rtt` | Orocos runtime | Public maintenance fork |
| `open62541` | OPC UA C stack used by the native RTT transport | Upstream tag `v1.4.15` |
| `open62541pp` | C++ API used by `rtt_opcua` | Upstream tag `v0.21.1` |
| `rtt_opcua` | Generic native OPC UA server, RTT object model, proxy, and port transport | `liufang-robot` upstream |
| `ocl` | deployer and OCL compatibility | Public maintenance fork |
| `orogen` | component and typekit generation | Public maintenance fork while generator fixes are needed |
| `typelib` | generator type support | Public maintenance fork while compatibility fixes are needed |
| `utilmm` | generator/runtime support | Public maintenance fork while compatibility fixes are needed |
| `utilrb` | autoproj and generator support | Upstream |
| `rtt_typelib` | RTT and Typelib bridge | Public maintenance fork while compatibility fixes are needed |

RTT itself owns the fixed-width built-in types. The retired
`stdint_typekit` package must not be added to the workspace or installed
prefix.

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
- keep those changes on public branch pins recorded in `autoproj/overrides.yml`
- use upstream for everything else

Initial public maintenance source set:

- `farbot`
- `rtlog-cpp`
- `rtt`
- `rtt_opcua`
- `ocl`
- `orogen`
- `typelib`
- `utilmm`
- `rtt_typelib`

Forks should carry focused portability work:

- newer compiler warning cleanup
- build-system fixes
- dependency discovery fixes
- distribution compatibility patches
- target-specific runtime fixes, such as the staged RTT Xenomai 3 work,
  when they stay inside the Orocos/Rock toolchain boundary

Upstream by default:

- `open62541` at the selected compatibility tag
- `open62541pp` at the selected compatibility tag
- `rtt_geometry`
- `utilrb`

The workspace builds `open62541pp` against the separately selected
`open62541` package. It does not depend on recursive Git submodules for this
dependency.

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
