# Dual-Organization Publication

This page defines how the maintained Orocos/Rock sources are published to both
`liufang-robot` and `OptimalCNC` while keeping each organization's root
workspace independently buildable.

## Decision

`liufang-robot` is the canonical development source for this workspace.
Maintained package commits are first published there and then synchronized to
the corresponding default branches in `OptimalCNC`.

`OptimalCNC/rock-orocos` is a self-contained distribution root, not an exact
Git mirror. Its package selections point to `OptimalCNC` forks, while the
`liufang-robot/rock-orocos` selections point to `liufang-robot` forks.

The official `open62541`, `open62541pp`, and `utilrb` selections remain on
their upstream repositories in both organizations.

## Prefix Channels

| Root repository | Upload reference | Consumer URL |
|---|---|---|
| `liufang-robot/rock-orocos` | `liufang-robot/orocos` | `https://prefix.dev/liufang-robot/orocos` |
| `OptimalCNC/rock-orocos` | `metanc/orocos` | `https://prefix.dev/metanc/orocos` |

Each channel authorizes only its corresponding root repository and the exact
`linux-packages.yml` and `windows-packages.yml` workflow files through
Repository Access. The `OptimalCNC` root publishes only to `metanc/orocos`;
the canonical root independently publishes only to `liufang-robot/orocos`.

## Repository Matrix

| Workspace package | `liufang-robot` repository | `OptimalCNC` repository | Published branch |
|---|---|---|---|
| Root workspace | `rock-orocos` | `rock-orocos` | `main` |
| `farbot` | `farbot` | `farbot` | `master` |
| `rtlog-cpp` | `rtlog-cpp` | `rtlog-cpp` | `main` |
| `rtt` | `rtt` | `rtt` | `dev` |
| `rtt_opcua` | `rtt_opcua` | `rtt_opcua` | `dev` |
| `ocl` | `ocl` | `ocl` | `dev` |
| `orogen` | `tools-orogen` | `tools-orogen` | `dev` |
| `typelib` | `tools-typelib` | `tools-typelib` | `dev` |
| `utilmm` | `utilmm` | `utilmm` | `dev` |
| `rtt_typelib` | `tools-rtt_typelib` | `tools-rtt_typelib` | `dev` |

All organization-owned repositories are public. Remote feature branches are
not part of this publication flow.

## Package Publication

Normal feature work still follows the repository's pull-request and review
rules. Publication begins only after the reviewed commits have been integrated
into the intended local default branch. Synchronizing that approved branch to
the organization remotes does not create a remote feature branch.

For each maintained package:

1. verify the local default branch and its tests;
2. fetch both organization remotes;
3. reject a non-fast-forward update instead of rewriting remote history;
4. push the verified default branch to `liufang-robot`;
5. fast-forward the same package commit to `OptimalCNC`;
6. verify that both remote branch names resolve to the intended commit.

The canonical local checkout tracks the `liufang` remote. Synchronization to
the `optimalcnc` remote is explicit because one local branch cannot track two
upstreams simultaneously. Autoproj's managed `autobuild` remote is left under
Autoproj control.

If an OptimalCNC branch ever contains unique commits, synchronization stops for
review. A reviewed merge may preserve both histories; force-pushing or deleting
the unique commits is not allowed by this workflow.

## Root Workspace Policy

The root repositories intentionally differ by one organization policy lineage.
The `liufang-robot/main` version selects `liufang-robot` for every maintained
fork. The `OptimalCNC/main` version selects `OptimalCNC` for the same packages.

The organization-specific root change updates these live policy groups
together:

- source selection and enforcement in `autoproj/overrides.yml`,
  `tools/build-windows-msvc.ps1`, `tools/check-source-provenance.rb`, and
  `tools/check-autoproj-policy.rb`;
- locked repository identities in `packaging/source-lock.json` and
  `tools/windows-source-lock.ps1`, while keeping the selected revisions equal
  across organizations;
- release repository guards and Prefix channel defaults in both package
  workflows, both release staging tools, and
  `tools/check-{linux,windows}-package-ci.rb`;
- repository metadata and maintainers in both Conda recipes; and
- consumer channels and repository links in the root and packaging READMEs,
  the Pixi example, mdBook configuration and package/release chapters, plus
  their documentation, activation, and release-manifest checks.

The organization-facing package policy and Xenomai playbook must name the
active fork set. This publication page must describe the behavior of the root
variant in which it appears.

Canonical changes are merged into the OptimalCNC lineage without removing its
organization policy commit. The OptimalCNC policy checks must pass after every
such merge.

## Validation Gates

Before publishing:

- all maintained worktrees must be free of uncommitted source changes;
- generated build directories and TaskBrowser history must remain untracked;
- package tests and root repository policy checks must pass;
- both root policy variants must pass `tools/check-autoproj-policy.rb`;
- the merged `OptimalCNC` tree must be compared directly with `liufang/main`,
  and every remaining file difference must belong to an organization policy
  group listed above;
- `git diff --check` must pass for every commit being published.

After publishing, query every remote default branch and compare its commit ID
with the expected local commit. A rejected push, missing permission, branch
protection rule, or unexpected remote commit stops the operation for review.
