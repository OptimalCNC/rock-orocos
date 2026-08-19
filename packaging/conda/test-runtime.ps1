Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$condaPrefix = if ($env:PREFIX) { $env:PREFIX } else { $env:CONDA_PREFIX }
if ([string]::IsNullOrWhiteSpace($condaPrefix)) {
    throw "Neither PREFIX nor CONDA_PREFIX identifies the package test environment."
}

$libraryPrefix = if ($env:LIBRARY_PREFIX) {
    $env:LIBRARY_PREFIX
} else {
    Join-Path $condaPrefix "Library"
}

$runtimeEnvironment = Join-Path $libraryPrefix "env.ps1"
if (-not (Test-Path -LiteralPath $runtimeEnvironment -PathType Leaf)) {
    throw "The orocos package did not install env.ps1 at $runtimeEnvironment"
}

. $runtimeEnvironment

if ($env:OROCOS_PREFIX -ne $libraryPrefix -or $env:OROCOS_TARGET -ne "win32") {
    throw "The runtime activation script exported the wrong prefix or target."
}
if ($env:PATH -match '(?i)(build[\\/]vcpkg|\.vcpkg)') {
    throw "The runtime PATH still refers to a vcpkg build checkout."
}

foreach ($relativePath in @(
        "bin\readline.dll",
        "bin\boost_filesystem-vc143-mt-x64-1_91.dll",
        "bin\libxml2.dll"
    )) {
    $path = Join-Path $libraryPrefix $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing packaged runtime dependency: $path"
    }
}

foreach ($command in @(
        "deployer-win32.exe",
        "rttscript-win32.exe",
        "deployer-opcua-win32.exe"
    )) {
    $executable = (Get-Command $command -ErrorAction Stop).Source
    & $executable --check --no-consolelog
    if ($LASTEXITCODE -ne 0) {
        throw "$command validation failed with exit code $LASTEXITCODE."
    }
}

$taskBrowser = (Get-Command "ctaskbrowser-opcua-win32.exe" -ErrorAction Stop).Source
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $taskBrowserHelp = & $taskBrowser --help 2>&1 | Out-String
} finally {
    $ErrorActionPreference = $savedErrorActionPreference
}
if ($taskBrowserHelp -notmatch "--import PACKAGE") {
    throw "The packaged OPC UA TaskBrowser failed its help check."
}
