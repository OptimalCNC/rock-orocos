# OptimalCNC Publication Sync Design

## Context

`liufang-robot` remains the canonical development source for the Orocos/Rock
toolchain, but `OptimalCNC` must remain an independently buildable and
publishable distribution root. Maintained package commits are identical in
both organizations. The root repositories intentionally differ where source
ownership, package metadata, Prefix channels, and publishing authorization are
organization-specific.

The current package branches have already been synchronized. The root branches
cannot be fast-forwarded because `OptimalCNC/main` contains its existing source
policy lineage while `liufang-robot/main` contains newer Windows build and
packaging work. The root update therefore requires a normal merge that
preserves both histories.

## Decisions

- Keep the dual-lineage root model described by
  `docs/src/dual-organization-publication.md`.
- Merge canonical root changes into the OptimalCNC lineage without force
  pushing or dropping its organization policy commits.
- Keep maintained package default branches byte-identical across both
  organizations.
- Keep functional build, test, packaging, release, and validation logic
  equivalent between root variants.
- Allow root variants to differ only in organization-owned source URLs,
  Prefix channel settings, publishing guards, package metadata, policy
  expectations, and explanatory documentation.
- Give each organization its own Prefix channel and release operation.

## Source Provenance

The OptimalCNC root must select the corresponding `OptimalCNC` repository for
every maintained toolchain package:

| Package | OptimalCNC repository | Branch |
|---|---|---|
| `farbot` | `OptimalCNC/farbot` | `master` |
| `rtlog-cpp` | `OptimalCNC/rtlog-cpp` | `main` |
| `rtt` | `OptimalCNC/rtt` | `dev` |
| `rtt_opcua` | `OptimalCNC/rtt_opcua` | `dev` |
| `ocl` | `OptimalCNC/ocl` | `dev` |
| `orogen` | `OptimalCNC/tools-orogen` | `dev` |
| `typelib` | `OptimalCNC/tools-typelib` | `dev` |
| `utilmm` | `OptimalCNC/utilmm` | `dev` |
| `rtt_typelib` | `OptimalCNC/tools-rtt_typelib` | `dev` |

This rule applies to every executable or configured source selector, including:

- `autoproj/overrides.yml`;
- repository defaults in `tools/build-windows-msvc.ps1`;
- repository entries in `packaging/source-lock.json`; and
- the tests and policy checks that enforce those selections.

There is no fallback from an OptimalCNC maintained source to `liufang-robot`.
The locked revisions remain identical to the canonical variant and must exist
in the selected OptimalCNC repository before the root can be published.

External sources are restricted to explicit third-party open-source
dependencies. The current allowlist is:

- `open62541/open62541`;
- `open62541pp/open62541pp`;
- `rock-core/tools-utilrb`;
- `rock-core/tools-metaruby`;
- `microsoft/vcpkg`; and
- upstream Autoproj package sets required by `autoproj/manifest` and their
  declared imports.

Policy validation must reject a maintained source outside `OptimalCNC` and an
external source that is not covered by the third-party allowlist.

## Root Organization Overlay

The merge retains the newer canonical implementation and applies the
OptimalCNC organization values consistently across these surfaces:

- Autoproj source selection and its policy test;
- Windows development-build repository defaults;
- the immutable Windows source lock;
- Conda package homepage, repository, documentation, and maintainer metadata;
- Windows package workflow channel constants and publishing repository guard;
- release-bundle channel metadata and its tests; and
- user, maintainer, package, and dual-publication documentation.

The organization overlay must not change package revisions, compilation
options, package contents, test coverage, version numbers, release validation,
or artifact immutability rules.

## Prefix Channels

The two root variants use independent Prefix channels:

| Root repository | Upload reference | Consumer URL | Website page |
|---|---|---|---|
| `liufang-robot/rock-orocos` | `liufang-robot/orocos` | `https://prefix.dev/liufang-robot/orocos` | `https://prefix.dev/channels/@liufang-robot/orocos` |
| `OptimalCNC/rock-orocos` | `metanc/orocos` | `https://prefix.dev/metanc/orocos` | `https://prefix.dev/channels/@metanc/orocos` |

Prefix upload commands use the canonical reference without `@`. Package
managers use the consumer URL without `/channels/@`. The website route is only
for human-facing channel administration.

Before the first OptimalCNC publication, the `@metanc/orocos` Repository
Access settings must authorize GitHub repository
`OptimalCNC/rock-orocos` and workflow `windows-packages.yml` with the minimum
permission required to upload packages.

## CI And Release Behavior

Both organizations retain the same release gate:

- pull requests, pushes to `main`, and manual workflow dispatches build and
  test without publishing;
- only a manually published, non-prerelease GitHub Release enters the publish
  job;
- the publish job verifies the tag, package version, repository commit,
  source lock, package metadata, and checksums;
- uploads never use `--force` or `--skip-existing`;
- a successful upload is followed by clean consumer tests against that
  organization's public channel; and
- OIDC write permission exists only in the publish job.

The OptimalCNC workflow publishes only when
`github.repository == 'OptimalCNC/rock-orocos'`, uploads to `metanc/orocos`,
and tests consumers through `https://prefix.dev/metanc/orocos`.

## Root Tags

The root variants have different commits because their organization overlays
differ. A release tag with the same version may therefore point to a different
commit in each remote repository.

The existing canonical `v0.1.0` tag must not be pushed to OptimalCNC. The root
synchronization publishes only `origin/main`. A later OptimalCNC GitHub Release
must create its release tag from the reviewed OptimalCNC `main` commit. No tag
is created as part of this synchronization.

## Synchronization Flow

1. Fetch both root remotes and all maintained package remotes.
2. Verify that each maintained package default branch resolves to the same
   commit in both organizations.
3. Merge `liufang/main` into local `optimal-main` without rewriting history.
4. Resolve organization-specific files to the OptimalCNC overlay while
   retaining equivalent functional code.
5. Add or update policy checks for source provenance, Prefix configuration,
   publishing identity, and package metadata.
6. Run the validation gates below.
7. Push local `optimal-main` to `origin/main` as a normal non-force update.
8. Query the remote branch after the push and confirm it resolves to the
   reviewed local commit.
9. Monitor the GitHub Actions runs triggered by the update.

Any merge conflict, unexpected remote-only commit, non-fast-forward push,
missing package commit, policy failure, build failure, or CI failure stops the
operation for review. The workflow never force-pushes either root or package
history.

## Validation

Before pushing the root:

- confirm there are no uncommitted tracked changes in maintained worktrees;
- confirm all maintained package branch commit IDs match across organizations;
- assert every OptimalCNC maintained source selector uses an OptimalCNC URL;
- assert every remaining external source is on the third-party allowlist;
- assert source-lock revisions are full immutable commits available from the
  selected repositories;
- run repository, Autoproj, Windows source-lock, and Windows package workflow
  policy checks;
- run `git diff --check` on the proposed root update; and
- compile, install, and validate the `gnulinux` layout using the OptimalCNC
  source configuration.

After pushing, monitor repository policy, native toolchain, Windows MSVC, and
Windows package workflows. Windows-hosted compilation remains the final proof
for the Windows-specific path.

## Non-Goals

- Combining both organizations into a dynamically selected exact root mirror.
- Publishing both organizations into one Prefix channel.
- Automatically publishing packages on every `main` push.
- Creating a GitHub Release or release tag during repository synchronization.
- Replacing official third-party sources with unnecessary organization forks.
