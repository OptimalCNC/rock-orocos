[CmdletBinding()]
param(
    [ValidateSet("Stage", "Verify")]
    [string]$Mode = "Verify",
    [string]$PackageDirectory = "packaging/conda/output/win-64",
    [string]$ReleaseDirectory = "packaging/conda/output/release",
    [string]$SourceLockPath = "packaging/source-lock.json",
    [string]$Channel = "liufang-robot/orocos",
    [string]$RepositoryCommit = "",
    [string]$ExpectedTag = "",
    [string]$ExpectedRepositoryCommit = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Container", "Leaf")]
        [string]$PathType
    )

    if (-not (Test-Path -LiteralPath $Path -PathType $PathType)) {
        throw "Expected $PathType path does not exist: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha256.ComputeHash($stream)
        }
        finally {
            $sha256.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
}

function Invoke-PackageInspect {
    param([Parameter(Mandatory = $true)][string]$PackagePath)

    $output = @(
        & rattler-build package inspect $PackagePath --all --json
    )
    if ($LASTEXITCODE -ne 0) {
        throw "rattler-build could not inspect $PackagePath"
    }

    try {
        return (($output -join [Environment]::NewLine) | ConvertFrom-Json)
    }
    catch {
        throw "rattler-build returned invalid JSON for ${PackagePath}: $($_.Exception.Message)"
    }
}

function Get-PackageRecords {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $files = @(
        Get-ChildItem -LiteralPath $Directory -File -Filter "*.conda" |
            Sort-Object Name
    )
    if ($files.Count -ne 2) {
        throw "Expected exactly two .conda files in $Directory, found $($files.Count)."
    }

    $records = @()
    foreach ($file in $files) {
        $metadata = Invoke-PackageInspect -PackagePath $file.FullName
        $hash = Get-FileSha256 -Path $file.FullName
        $records += [PSCustomObject]@{
            File = $file
            Metadata = $metadata
            Sha256 = $hash
            Paths = @($metadata.paths.paths | ForEach-Object { $_._path })
        }
    }

    return $records
}

function Test-PackageSet {
    param([Parameter(Mandatory = $true)][object[]]$Records)

    $byName = @{}
    foreach ($record in $Records) {
        $index = $record.Metadata.index
        $name = [string]$index.name
        if ($byName.ContainsKey($name)) {
            throw "Duplicate package output for $name."
        }
        $byName[$name] = $record

        if ([string]$index.subdir -ne "win-64") {
            throw "$($record.File.Name) targets '$($index.subdir)', expected win-64."
        }
        $expectedFilename = "$name-$($index.version)-$($index.build).conda"
        if ($record.File.Name -cne $expectedFilename) {
            throw "$($record.File.Name) does not match package metadata filename $expectedFilename."
        }
    }

    $expectedNames = @("orocos", "orocos-dev")
    foreach ($name in $expectedNames) {
        if (-not $byName.ContainsKey($name)) {
            throw "Missing expected package output $name."
        }
    }
    if ($byName.Count -ne $expectedNames.Count) {
        throw "The release contains an unexpected package output."
    }

    $runtime = $byName["orocos"]
    $development = $byName["orocos-dev"]
    $version = [string]$runtime.Metadata.index.version
    if ([string]$development.Metadata.index.version -cne $version) {
        throw "Runtime and development package versions do not match."
    }

    $runtimeSpec = "orocos ==$version $($runtime.Metadata.index.build)"
    $developmentDependencies = @($development.Metadata.index.depends | ForEach-Object { [string]$_ })
    if ($developmentDependencies -cnotcontains $runtimeSpec) {
        throw "orocos-dev must depend on the exact runtime build '$runtimeSpec'."
    }

    $developmentPaths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($path in $development.Paths) {
        [void]$developmentPaths.Add([string]$path)
    }
    $overlap = @(
        $runtime.Paths | Where-Object { $developmentPaths.Contains([string]$_) }
    )
    if ($overlap.Count -gt 0) {
        throw "Runtime and development packages overlap at $($overlap.Count) paths."
    }

    return [PSCustomObject]@{
        ByName = $byName
        Runtime = $runtime
        Development = $development
        Version = $version
        OverlapCount = $overlap.Count
    }
}

function Test-LocalRepodata {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][object[]]$Records
    )

    $repodataPath = Join-Path $Directory "repodata.json"
    $resolvedRepodata = Resolve-ExistingPath -Path $repodataPath -PathType Leaf
    $repodata = Get-Content -LiteralPath $resolvedRepodata -Raw | ConvertFrom-Json
    $packageGroup = $repodata.PSObject.Properties["packages.conda"].Value

    foreach ($record in $Records) {
        $property = $packageGroup.PSObject.Properties[$record.File.Name]
        if ($null -eq $property) {
            throw "repodata.json is missing $($record.File.Name)."
        }
        $entry = $property.Value
        if ([string]$entry.sha256 -cne $record.Sha256) {
            throw "repodata.json has a stale SHA256 for $($record.File.Name)."
        }
        if ([long]$entry.size -ne [long]$record.File.Length) {
            throw "repodata.json has a stale size for $($record.File.Name)."
        }
    }
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Test-ReleaseBundle {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$ExpectedSourceLock,
        [Parameter(Mandatory = $true)][string]$ExpectedChannel,
        [string]$Tag = "",
        [string]$Commit = ""
    )

    $manifestPath = Resolve-ExistingPath `
        -Path (Join-Path $Directory "release-manifest.json") `
        -PathType Leaf
    $checksumsPath = Resolve-ExistingPath `
        -Path (Join-Path $Directory "SHA256SUMS.txt") `
        -PathType Leaf
    $bundledSourceLock = Resolve-ExistingPath `
        -Path (Join-Path $Directory "source-lock.json") `
        -PathType Leaf
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    if ([int]$manifest.schema_version -ne 1) {
        throw "Unsupported release manifest schema version '$($manifest.schema_version)'."
    }
    if ([string]$manifest.channel -cne $ExpectedChannel) {
        throw "Release manifest channel '$($manifest.channel)' does not match '$ExpectedChannel'."
    }
    if ([string]$manifest.target_platform -cne "win-64") {
        throw "Release manifest target '$($manifest.target_platform)' does not match win-64."
    }
    if ($ExpectedChannel.Contains("@")) {
        throw "Prefix channel references must not contain '@'."
    }
    if ($Tag -and $Tag -cne "v$($manifest.version)") {
        throw "Release tag '$Tag' must exactly match package version v$($manifest.version)."
    }
    if ($Commit -and [string]$manifest.repository_commit -cne $Commit) {
        throw "Release manifest commit '$($manifest.repository_commit)' does not match '$Commit'."
    }
    if ([string]$manifest.repository_commit -and
        [string]$manifest.repository_commit -cnotmatch "^[0-9a-f]{40}$") {
        throw "Release manifest repository_commit must be a full lowercase Git SHA."
    }
    if ([string]$manifest.source_lock.filename -cne "source-lock.json") {
        throw "Release manifest must identify source-lock.json."
    }

    $expectedSourceLockHash = Get-FileSha256 -Path $ExpectedSourceLock
    $bundledSourceLockHash = Get-FileSha256 -Path $bundledSourceLock
    if ($bundledSourceLockHash -cne $expectedSourceLockHash) {
        throw "The bundled source lock does not match the release commit."
    }
    if ([string]$manifest.source_lock.sha256 -cne $bundledSourceLockHash) {
        throw "Release manifest source-lock checksum does not match source-lock.json."
    }

    $records = @(Get-PackageRecords -Directory $Directory)
    $packageSet = Test-PackageSet -Records $records
    if ([string]$manifest.version -cne $packageSet.Version) {
        throw "Release manifest version does not match package metadata."
    }

    $manifestPackages = @($manifest.packages)
    if ($manifestPackages.Count -ne 2) {
        throw "Release manifest must describe exactly two packages."
    }
    foreach ($record in $records) {
        $name = [string]$record.Metadata.index.name
        $matches = @($manifestPackages | Where-Object { [string]$_.name -ceq $name })
        if ($matches.Count -ne 1) {
            throw "Release manifest must contain exactly one record for $name."
        }
        $entry = $matches[0]
        if ([string]$entry.filename -cne $record.File.Name -or
            [string]$entry.version -cne [string]$record.Metadata.index.version -or
            [string]$entry.build -cne [string]$record.Metadata.index.build -or
            [int]$entry.build_number -ne [int]$record.Metadata.index.build_number -or
            [string]$entry.subdir -cne [string]$record.Metadata.index.subdir -or
            [long]$entry.bytes -ne [long]$record.File.Length -or
            [string]$entry.sha256 -cne $record.Sha256 -or
            [int]$entry.paths -ne $record.Paths.Count) {
            throw "Release manifest metadata does not match $($record.File.Name)."
        }

        $manifestDependencies = @($entry.depends | ForEach-Object { [string]$_ } | Sort-Object)
        $packageDependencies = @(
            $record.Metadata.index.depends | ForEach-Object { [string]$_ } | Sort-Object
        )
        if (@(Compare-Object $manifestDependencies $packageDependencies -CaseSensitive).Count -ne 0) {
            throw "Release manifest dependencies do not match $($record.File.Name)."
        }
    }

    $expectedChecksumLines = @(
        $manifestPackages |
            Sort-Object filename |
            ForEach-Object { "$($_.sha256)  $($_.filename)" }
    )
    $expectedChecksumLines += "$bundledSourceLockHash  source-lock.json"
    $actualChecksumLines = @([System.IO.File]::ReadAllLines($checksumsPath))
    if (@(Compare-Object $expectedChecksumLines $actualChecksumLines -CaseSensitive).Count -ne 0) {
        throw "SHA256SUMS.txt does not match the release bundle."
    }

    Write-Host (
        "Verified release bundle for {0}: {1} runtime files, {2} development files, no overlap." -f
        $packageSet.Version,
        $packageSet.Runtime.Paths.Count,
        $packageSet.Development.Paths.Count
    )
}

if (-not (Get-Command rattler-build -ErrorAction SilentlyContinue)) {
    throw "rattler-build is required; run this script through the Pixi package environment."
}

$resolvedSourceLock = Resolve-ExistingPath -Path $SourceLockPath -PathType Leaf
$releasePath = Get-FullPath -Path $ReleaseDirectory

if ($Mode -eq "Stage") {
    if ($RepositoryCommit -and $RepositoryCommit -cnotmatch "^[0-9a-f]{40}$") {
        throw "RepositoryCommit must be a full lowercase Git SHA."
    }
    $packagePath = Resolve-ExistingPath -Path $PackageDirectory -PathType Container
    $records = @(Get-PackageRecords -Directory $packagePath)
    $packageSet = Test-PackageSet -Records $records
    Test-LocalRepodata -Directory $packagePath -Records $records

    if (Test-Path -LiteralPath $releasePath) {
        if (-not (Test-Path -LiteralPath $releasePath -PathType Container)) {
            throw "Release path exists but is not a directory: $releasePath"
        }
        $existing = @(Get-ChildItem -LiteralPath $releasePath -Force)
        if ($existing.Count -gt 0) {
            throw "Release directory must be empty before staging: $releasePath"
        }
    }
    else {
        New-Item -ItemType Directory -Path $releasePath | Out-Null
    }

    foreach ($record in $records) {
        Copy-Item -LiteralPath $record.File.FullName -Destination $releasePath
    }
    Copy-Item -LiteralPath $resolvedSourceLock -Destination (Join-Path $releasePath "source-lock.json")

    $sourceLockHash = Get-FileSha256 -Path $resolvedSourceLock
    $manifestPackages = @(
        $records |
            Sort-Object { $_.Metadata.index.name } |
            ForEach-Object {
                [ordered]@{
                    name = [string]$_.Metadata.index.name
                    version = [string]$_.Metadata.index.version
                    build = [string]$_.Metadata.index.build
                    build_number = [int]$_.Metadata.index.build_number
                    subdir = [string]$_.Metadata.index.subdir
                    filename = $_.File.Name
                    bytes = [long]$_.File.Length
                    sha256 = $_.Sha256
                    paths = $_.Paths.Count
                    depends = @($_.Metadata.index.depends | ForEach-Object { [string]$_ })
                }
            }
    )
    $manifest = [ordered]@{
        schema_version = 1
        channel = $Channel
        target_platform = "win-64"
        version = $packageSet.Version
        repository_commit = $RepositoryCommit
        source_lock = [ordered]@{
            filename = "source-lock.json"
            sha256 = $sourceLockHash
        }
        packages = $manifestPackages
    }
    $manifestJson = ($manifest | ConvertTo-Json -Depth 8) + "`n"
    Write-Utf8File `
        -Path (Join-Path $releasePath "release-manifest.json") `
        -Content $manifestJson

    $checksumLines = @(
        $manifestPackages |
            Sort-Object filename |
            ForEach-Object { "$($_.sha256)  $($_.filename)" }
    )
    $checksumLines += "$sourceLockHash  source-lock.json"
    Write-Utf8File `
        -Path (Join-Path $releasePath "SHA256SUMS.txt") `
        -Content (($checksumLines -join "`n") + "`n")

    Test-ReleaseBundle `
        -Directory $releasePath `
        -ExpectedSourceLock $resolvedSourceLock `
        -ExpectedChannel $Channel `
        -Commit $RepositoryCommit
    Write-Host "Prepared release bundle at $releasePath"
}
else {
    $resolvedRelease = Resolve-ExistingPath -Path $releasePath -PathType Container
    Test-ReleaseBundle `
        -Directory $resolvedRelease `
        -ExpectedSourceLock $resolvedSourceLock `
        -ExpectedChannel $Channel `
        -Tag $ExpectedTag `
        -Commit $ExpectedRepositoryCommit
}
