[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "windows-source-lock.ps1")

$sourceLockPath = Join-Path $PSScriptRoot "..\packaging\source-lock.json"
$sourceLock = Import-OrocosWindowsSourceLock -Path $sourceLockPath
$expectedCount = @(Get-OrocosWindowsExpectedSourceNames).Count
if ($sourceLock.Count -ne $expectedCount) {
    throw "Expected $expectedCount locked sources, got $($sourceLock.Count)."
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ("orocos-source-lock-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

function Assert-LockRejected {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Contents,
        [Parameter(Mandatory = $true)][string]$ExpectedMessage
    )

    $path = Join-Path $temporaryRoot "$Name.json"
    [System.IO.File]::WriteAllText($path, $Contents, [System.Text.UTF8Encoding]::new($false))

    $failure = $null
    try {
        $null = Import-OrocosWindowsSourceLock -Path $path
    } catch {
        $failure = $_.Exception.Message
    }

    if ($null -eq $failure) {
        throw "Invalid source-lock case '$Name' was accepted."
    }
    if (-not $failure.Contains($ExpectedMessage)) {
        throw "Source-lock case '$Name' failed with '$failure', expected '$ExpectedMessage'."
    }
}

function Copy-SourceLockDocument {
    Get-Content -LiteralPath $sourceLockPath -Raw | ConvertFrom-Json
}

try {
    Assert-LockRejected -Name "malformed" -Contents "{" -ExpectedMessage "Invalid JSON"

    $document = Copy-SourceLockDocument
    $document.schema_version = 2
    Assert-LockRejected -Name "schema" `
        -Contents ($document | ConvertTo-Json -Depth 5) `
        -ExpectedMessage "schema version"

    $document = Copy-SourceLockDocument
    $document.sources = @($document.sources | Select-Object -Skip 1)
    Assert-LockRejected -Name "missing" `
        -Contents ($document | ConvertTo-Json -Depth 5) `
        -ExpectedMessage "missing source(s)"

    $document = Copy-SourceLockDocument
    $document.sources[0].name = "not-a-source"
    Assert-LockRejected -Name "unknown" `
        -Contents ($document | ConvertTo-Json -Depth 5) `
        -ExpectedMessage "unknown source"

    $document = Copy-SourceLockDocument
    $document.sources += $document.sources[0]
    Assert-LockRejected -Name "duplicate" `
        -Contents ($document | ConvertTo-Json -Depth 5) `
        -ExpectedMessage "duplicate source"

    $document = Copy-SourceLockDocument
    $document.sources[0].revision = "main"
    Assert-LockRejected -Name "branch-ref" `
        -Contents ($document | ConvertTo-Json -Depth 5) `
        -ExpectedMessage "full 40-character Git commit"

    $document = Copy-SourceLockDocument
    $document.sources[0].repository = " "
    Assert-LockRejected -Name "blank-repository" `
        -Contents ($document | ConvertTo-Json -Depth 5) `
        -ExpectedMessage "invalid repository"

    $document = Copy-SourceLockDocument
    $document.sources[0] | Add-Member -NotePropertyName "ref" -NotePropertyValue "main"
    Assert-LockRejected -Name "unknown-field" `
        -Contents ($document | ConvertTo-Json -Depth 5) `
        -ExpectedMessage "unknown field(s)"
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Host "Windows source lock tests passed ($expectedCount sources, 8 rejection cases)."
