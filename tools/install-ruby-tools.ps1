[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prefix,
    [Parameter(Mandatory = $true)]
    [string]$UtilrbSource,
    [Parameter(Mandatory = $true)]
    [string]$MetarubySource,
    [Parameter(Mandatory = $true)]
    [string]$OrogenSource
)

$ErrorActionPreference = "Stop"

function Convert-ToFullPath {
    param([string]$Path)

    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Invoke-Native {
    $FilePath = $args[0]
    $ArgumentList = @()
    if ($args.Count -gt 1) {
        $ArgumentList = $args[1..($args.Count - 1)]
    }

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath exited with code $LASTEXITCODE"
    }
}

function Install-RemoteGem {
    param(
        [string]$Name,
        [string]$Version
    )

    $arguments = @(
        "install",
        "--install-dir", $script:GemHome,
        "--bindir", $script:BinDirectory,
        "--no-document"
    )
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $arguments += @("--version", $Version)
    }
    $arguments += $Name
    Invoke-Native gem @arguments
}

function Install-LocalGem {
    param([string]$Source)

    $gemSpec = Get-ChildItem -LiteralPath $Source -Filter "*.gemspec" -File |
        Select-Object -First 1
    if ($null -eq $gemSpec) {
        throw "No gemspec found under $Source"
    }

    $gemPath = Join-Path $script:TemporaryDirectory ($gemSpec.BaseName + ".gem")
    Push-Location $Source
    try {
        Invoke-Native gem build $gemSpec.Name --output $gemPath
    } finally {
        Pop-Location
    }

    Invoke-Native gem install `
        --install-dir $script:GemHome `
        --bindir $script:BinDirectory `
        --local `
        --no-document `
        --ignore-dependencies `
        $gemPath
}

$Prefix = Convert-ToFullPath $Prefix
$UtilrbSource = Convert-ToFullPath $UtilrbSource
$MetarubySource = Convert-ToFullPath $MetarubySource
$OrogenSource = Convert-ToFullPath $OrogenSource
$GemHome = Join-Path $Prefix "toolchain\gems"
$BinDirectory = Join-Path $Prefix "toolchain\bin"
$TemporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) `
    ("orocos-rock-ruby-" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Force -Path $GemHome | Out-Null
New-Item -ItemType Directory -Force -Path $BinDirectory | Out-Null
New-Item -ItemType Directory -Path $TemporaryDirectory | Out-Null

$savedGemHome = $env:GEM_HOME
$savedGemPath = $env:GEM_PATH
$env:GEM_HOME = $GemHome
$env:GEM_PATH = $GemHome

try {
    Install-RemoteGem -Name "facets" -Version "3.1.0"
    Install-RemoteGem -Name "backports" -Version "3.25.3"
    Install-RemoteGem -Name "base64" -Version "0.3.0"
    Install-RemoteGem -Name "rexml" -Version "3.4.4"
    Install-RemoteGem -Name "kramdown" -Version "2.5.2"
    Install-RemoteGem -Name "rake" -Version "13.4.2"

    Install-LocalGem -Source $UtilrbSource
    Install-LocalGem -Source $MetarubySource
    Install-LocalGem -Source $OrogenSource
} finally {
    $env:GEM_HOME = $savedGemHome
    $env:GEM_PATH = $savedGemPath
    if (Test-Path -LiteralPath $TemporaryDirectory) {
        Remove-Item -LiteralPath $TemporaryDirectory -Recurse -Force
    }
}

foreach ($command in @("orogen.bat", "typegen.bat")) {
    $path = Join-Path $BinDirectory $command
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Ruby tool installation did not create $path"
    }
}
