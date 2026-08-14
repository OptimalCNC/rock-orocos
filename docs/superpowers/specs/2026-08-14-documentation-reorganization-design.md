# Stable Public Documentation Reorganization Design

Date: 2026-08-14

Status: Approved for implementation planning

## Context

The current mdBook contains durable user guidance, maintainer policy, shipped
technical designs, active product proposals, completed implementation plans,
and point-in-time verification evidence in one flat `Reference` section.
Several Markdown sources are not present in `SUMMARY.md`, while completed plans
remain visible as if they were active instructions.

The repository needs one stable public book. It will not retain a historical
documentation archive.

## Goals

- organize the book by reader and document lifecycle;
- document only shipped behavior in guides and reference chapters;
- retain approved but unimplemented work in an explicit TODO section;
- migrate durable information out of completed plans before deleting them;
- remove redirects, stale execution checklists, temporary paths, and
  point-in-time transcripts;
- prevent orphan pages and ambiguous document status from returning; and
- preserve the existing URLs of durable public chapters where practical.

## Non-Goals

- preserve a historical archive of plans or design iterations;
- retain completed checklists for traceability;
- document downstream MetaNC application behavior;
- redesign the Orocos/Rock toolchain itself; or
- publish generated `docs/book/` output.

## Information Architecture

The public navigation has five reader-facing entries:

1. Overview
2. User Guide
3. Maintainer Guide
4. Reference
5. Planned Work / TODO

The source tree is:

```text
docs/src/
|-- SUMMARY.md
|-- index.md
|-- user-guide.md
|-- maintainer-guide.md
|-- reference.md
|-- architecture.md
|-- package-policy.md
|-- install-contract.md
|-- bootstrap-workflow.md
|-- opcua-reference.md
|-- xenomai3-integration.md
|-- dual-organization-publication.md
|-- package-test-results.md
`-- todo/
    |-- index.md
    |-- opcua-native-task-state-operations-design.md
    |-- opcua-security-prd.md
    `-- deployer-tui-prd.md
```

Durable page paths remain unchanged unless a page is new. Planned pages move
under `todo/` because their lifecycle is different from the supported
reference contract.

## Document Lifecycle

```mermaid
flowchart LR
    TODO["Planned work under todo/"] -->|implemented and verified| STABLE["Stable guide or reference"]
    STABLE -->|superseded| REWRITE["Update durable chapter"]
    REWRITE --> DELETE["Delete obsolete source"]
    TODO -->|cancelled| DELETE
```

The rules are:

- Guides and reference pages describe current supported behavior only.
- Unimplemented behavior lives under `todo/` and is visibly marked as planned.
- Once planned work ships, its durable contract is merged into the appropriate
  guide or reference chapter and the TODO source is deleted.
- Completed implementation plans are deleted after durable behavior and
  verification requirements have been migrated.
- There is no archive, redirect stub, or completed-plan section.

> [!IMPORTANT]
> When a historical plan conflicts with the current source, installed-prefix
> behavior, or durable policy documents, the current implementation and
> installed-prefix contract are authoritative.

## File Disposition

### Keep And Improve

| File | Result |
|---|---|
| `index.md` | Present the book entry points and distinguish supported documentation from TODO work. |
| `user-guide.md` | Keep supported install, environment, OPC UA, and type-name workflows. |
| `maintainer-guide.md` | Keep current script flow, maintenance rules, and validation entry points. |
| `reference.md` | Become a concise map of durable contracts. |
| `architecture.md` | Remain the repository boundary and non-goals source of truth. |
| `package-policy.md` | Remain the package and source-selection policy. |
| `install-contract.md` | Remain the downstream installed-prefix contract. |
| `bootstrap-workflow.md` | Keep the repeatable workspace lifecycle without phase-one language. |
| `xenomai3-integration.md` | Separate current supported behavior from remaining limitations and absorb shipped test-plan outcomes. |
| `dual-organization-publication.md` | Keep only the standing publication policy and current repository matrix. |
| `package-test-results.md` | Become a durable verification matrix; remove temporary directories, transcripts, and one-off commit snapshots. |

### Add

| File | Purpose |
|---|---|
| `opcua-reference.md` | Consolidate the shipped native OPC UA lifecycle, datatype, RTT mapping, port, proxy, and safety contracts. |
| `todo/index.md` | Explain TODO status and list approved unimplemented work. |

### Move Into TODO

| Current file | Destination |
|---|---|
| `opcua-native-task-state-operations-design.md` | `todo/opcua-native-task-state-operations-design.md` |
| `opcua-security-prd.md` | `todo/opcua-security-prd.md` |
| `deployer-tui-prd.md` | `todo/deployer-tui-prd.md` |

Each TODO document retains its useful product and technical design, but gains
a consistent status callout, a `TODO` section, acceptance criteria, and a clear
statement that it is not part of the current install contract.

### Delete After Migration

The following files are completed, superseded, redundant, redirects, or
point-in-time execution evidence:

- `for-maintainers.md`
- `modernization-plan.md`
- `cpp20-opcua-modernization-design.md`
- `dual-organization-publication-plan.md`
- `opcua-custom-datatype-verification.md`
- `opcua-deployer-lifecycle-design.md`
- `opcua-deployer-lifecycle-plan.md`
- `opcua-port-direction-protocol-design.md`
- `opcua-port-direction-protocol-plan.md`
- `opcua-rtt-interface-mapping-design.md`
- `opcua-rtt-interface-mapping-plan.md`
- `opcua-sparse-resource-categories-plan.md`
- `orocos-opcua-custom-datatype-design.md`
- `orocos-opcua-custom-datatype-plan.md`
- `opcua-taskbrowser-custom-datatype-evaluation-plan.md`
- `xenomai-opcua-test-harness-plan.md`
- `xenomai-rtt-test-link-plan.md`

## Content Migration

### OPC UA Reference

`opcua-reference.md` consolidates only shipped behavior from the completed OPC
UA documents. It covers:

- loopback endpoint configuration and explicit startup;
- process-wide datatype registration and freeze behavior;
- strict, static, whole-component publication;
- complete recursive RTT resource mapping;
- operation, property, attribute, constant, nested-service, and generated port
  service behavior;
- typed port data transfer, numeric status and direction contracts, and sparse
  resource categories;
- TaskContext proxy reconstruction and TaskBrowser behavior;
- publication failure, unsupported-resource diagnostics, lifetime, and unload
  restrictions; and
- current security and non-loopback limitations.

Implementation task sequences, feature-worktree paths, commit hashes, temporary
probe locations, RED/GREEN transcripts, and superseded behavior are not copied.

### Other Durable Chapters

- Current C++20 and canonical type-name requirements remain in the user guide,
  package policy, and relevant reference text.
- Shipped Xenomai RTT link and OCL test-lifecycle outcomes move into
  `xenomai3-integration.md` and the verification matrix.
- The executed dual-organization plan contributes only standing rules to
  `dual-organization-publication.md`.
- Repeatable validation commands remain in the maintainer guide and
  `package-test-results.md`; one-time evidence is removed.

## TODO Page Contract

Every page below `todo/` starts with an mdBook callout equivalent to:

```md
> [!IMPORTANT]
> Status: Planned and not implemented. This page is not part of the current
> install contract.
```

Each page must contain:

- the current problem or capability gap;
- the approved design or product requirements;
- a `TODO` section containing the remaining implementation outcomes;
- acceptance criteria; and
- links to the stable contracts it must preserve.

TODO checkboxes describe outcomes, not detailed agent execution commands.

## Navigation And Link Integrity

`SUMMARY.md` is the authoritative inventory of public Markdown sources.
Every Markdown file below `docs/src/`, except `SUMMARY.md`, must be reachable
from it.

The repository policy checker will validate:

- every source page is present in `SUMMARY.md`;
- every local Markdown target referenced by `SUMMARY.md` exists;
- no removed filename remains in repository Markdown links;
- every page under `todo/`, except its index, has the planned-status marker and
  a `TODO` section; and
- completed implementation-plan files do not reappear outside `todo/`.

Internal links are updated to point at the consolidated reference or TODO page
rather than deleted plans.

## Verification

The reorganization is complete when all of these pass from the repository
root:

```bash
ruby tools/check-repository-policy.rb
mdbook build docs --dest-dir /tmp/orocos-rock-docs-book
mdbook test docs
git diff --check
```

A final source scan must also show:

- no Markdown source omitted from `SUMMARY.md`;
- no reference to a deleted filename;
- no concrete generated `/tmp` evidence path in the stable public chapters
  (generic `/tmp` validation guidance remains allowed); and
- no generated `docs/book/` change.

## Acceptance Criteria

- The book exposes only supported guides/reference material and an explicitly
  separate TODO section.
- The three approved unimplemented designs remain available under `todo/`.
- All 17 obsolete or completed files are removed after durable migration.
- Shipped OPC UA behavior is described by one coherent reference chapter.
- Stable core source paths used by `README.md`, `AGENTS.md`, and repository
  policy checks remain valid.
- Every source page is navigable and the mdBook builds and tests successfully.
- Repository checks prevent new orphan pages and unlabeled planned work.
