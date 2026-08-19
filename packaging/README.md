# Conda Packaging

This directory owns the relocatable Conda packages intended for the
`liufang-robot/orocos` prefix.dev channel. Building and testing do not upload
anything; publication remains a separate release action.

The first Windows release has two `win-64` outputs:

- `orocos` contains the runtime executables, DLLs, plugins, typekits, and OPC
  UA support.
- `orocos-dev` contains headers, import libraries, build metadata, OroGen, and
  Typegen. It depends on the exact matching `orocos` build.

The recipe uses a Rattler-Build staging output so that the complete toolchain
is compiled once before its files are divided between the runtime and
development packages.

## Source-Locked Build

`source-lock.json` records the repository URL and exact 40-character commit
for every Git checkout consumed by the Windows build, including vcpkg. The
strict parser rejects missing, duplicate, unknown, or moving revisions.

Reproduce the release candidate prefix with:

```powershell
pixi install --locked
pixi run --locked windows-build -- `
  -SourceLockPath packaging/source-lock.json
```

Do not combine `-SourceLockPath` with an individual repository or ref
override. Omit `-SourceLockPath` when intentionally testing development
branches.

Run the focused lock contract test with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/test-windows-source-lock.ps1
```

## Build And Test

Install the locked packaging environment, render the solved recipe, then build
both packages:

```powershell
pixi install --locked -e package
pixi run --locked package-render
pixi run --locked package-build
```

`package-build` compiles the source-locked toolchain once, prepares a
relocatable prefix, divides it into non-overlapping runtime and development
outputs, and tests both outputs in isolated environments. The development test
uses the installed `orogen` and `typegen` to generate and compile fresh
downstream projects. After both tests pass, the task force-reindexes the local
channel so a repeated build of the same version and build number cannot leave
stale package hashes in `repodata.json`.

Successful artifacts are written below `conda/output/win-64`. Failed artifacts
are moved below `conda/output/broken` and must never be uploaded.

## CI And Prefix Publication

`.github/workflows/windows-packages.yml` applies the same package contract on
GitHub-hosted Windows runners:

- pull requests, pushes to `main`, and manual runs build and test the packages
  without publishing them;
- every successful build retains a release bundle containing the two packages,
  `source-lock.json`, `SHA256SUMS.txt`, and a structured release manifest;
- a published, non-prerelease GitHub Release runs the same build, verifies that
  its tag exactly matches the package version, and publishes the verified
  bundle; and
- after upload, fresh runtime and development environments install from the
  public Prefix channel and repeat the consumer checks.

Publication is additionally restricted to the canonical
`liufang-robot/rock-orocos` repository. The `OptimalCNC/rock-orocos` mirror can
run package CI, but a release there cannot publish these packages.

Configure Prefix once before publishing the first release:

1. Open the `liufang-robot/orocos` channel settings and select Repository
   Access (formerly Trusted Publishers).
2. Add the GitHub repository `liufang-robot/rock-orocos` and the exact workflow
   filename `windows-packages.yml`.
3. Grant the repository the minimum permission that allows package uploads;
   delete and lifecycle permissions are not required.

The publish job requests `id-token: write` only in that release job. Prefix
exchanges this GitHub OIDC identity for short-lived access, so no
`PREFIX_API_KEY` GitHub secret is required.

For release `0.1.0`, first let the workflow pass on `main`, then create and
publish GitHub Release `v0.1.0` at that exact commit. Do not upload the local
Step 5 files first: CI is the sole publisher, so a package filename never maps
to two independently built byte streams. A rerun that encounters an existing
filename fails intentionally; inspect the channel instead of using `--force`
or `--skip-existing`.

## Consume The Local Packages

Test the same dependency path a downstream Pixi workspace will use. The local
channel root is the directory above `win-64`, not the `win-64` directory
itself:

```powershell
pixi exec --spec "orocos-dev==0.1.0" `
  --channel "file:///D:/affairs/rock-orocos/packaging/conda/output" `
  --channel conda-forge `
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  ". (`$env:CONDA_PREFIX + '\Library\dev-env.ps1'); orogen --version"
```

For release validation, use separate clean Pixi workspaces for `orocos` and
`orocos-dev`. The runtime workspace must contain neither `orocos-dev` nor
development headers. The development workspace must resolve the exact runtime
build pinned by `orocos-dev`; run the same downstream OroGen and Typegen build
covered by `conda/test-dev.ps1` from that installed environment.

After publication, replace the local channel with
`https://prefix.dev/liufang-robot/orocos`. A downstream workspace normally
declares `orocos-dev`; its exact dependency installs the matching `orocos`
runtime package.

Do not upload until both package tests and the local-channel consumer check
pass. Package filenames are immutable: correct a published build by increasing
the build number, never by replacing the existing file.

The relocation audit rejects workspace and build paths in text configuration
or launcher files. MSVC and vcpkg binaries can still contain non-functional
source or PDB path strings; these are debug records and are not used for
runtime or development dependency discovery.
