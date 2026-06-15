[CmdletBinding()]
param(
    [string]$Workspace = (Join-Path (Get-Location) "build\windows-msvc"),
    [string]$Prefix = (Join-Path (Get-Location) "install\windows-msvc"),
    [string]$VcpkgRoot = (Join-Path (Get-Location) "vcpkg"),
    [string]$Log4cppRef = "dev",
    [string]$RttRef = "dev",
    [string]$OclRef = "dev",
    [string]$Generator = "Visual Studio 17 2022"
)

$ErrorActionPreference = "Stop"

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Script
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Script
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

function Invoke-NativeWithRetry {
    $Attempts = 3
    $DelaySeconds = 5
    $Command = $args

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            Invoke-Native @Command
            return
        } catch {
            if ($attempt -eq $Attempts) {
                throw
            }

            Write-Warning "Command failed on attempt $attempt/${Attempts}: $($_.Exception.Message)"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Convert-ToFullPath {
    param([string]$Path)

    $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Sync-GitRepository {
    param(
        [string]$Repository,
        [string]$Ref,
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath (Join-Path $Path ".git"))) {
        Invoke-NativeWithRetry git clone --no-checkout --filter=blob:none $Repository $Path
    }

    Invoke-NativeWithRetry git -C $Path fetch --depth 1 origin -- $Ref
    Invoke-Native git -C $Path checkout --force FETCH_HEAD
}

$Workspace = Convert-ToFullPath $Workspace
$Prefix = Convert-ToFullPath $Prefix
$VcpkgRoot = Convert-ToFullPath $VcpkgRoot
$Platform = "x64"
$VcpkgTriplet = "x64-windows"

$Log4cppSource = Join-Path $Workspace "src\log4cpp"
$RttSource = Join-Path $Workspace "src\rtt"
$OclSource = Join-Path $Workspace "src\ocl"
$Log4cppBuild = Join-Path $Workspace "build\log4cpp"
$RttBuild = Join-Path $Workspace "build\rtt"
$OclBuild = Join-Path $Workspace "build\ocl"

New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
New-Item -ItemType Directory -Force -Path $Prefix | Out-Null

$env:OROCOS_TARGET = "win32"

Invoke-Step "Check out source repositories" {
    Sync-GitRepository -Repository "https://github.com/liufang-robot/log4cpp.git" -Ref $Log4cppRef -Path $Log4cppSource
    Sync-GitRepository -Repository "https://github.com/liufang-robot/rtt.git" -Ref $RttRef -Path $RttSource
    Sync-GitRepository -Repository "https://github.com/liufang-robot/ocl.git" -Ref $OclRef -Path $OclSource
}

Invoke-Step "Set up vcpkg" {
    if (-not (Test-Path -LiteralPath (Join-Path $VcpkgRoot "vcpkg.exe"))) {
        Invoke-NativeWithRetry git clone https://github.com/microsoft/vcpkg.git $VcpkgRoot
        Invoke-Native (Join-Path $VcpkgRoot "bootstrap-vcpkg.bat") -disableMetrics
    }
}

$VcpkgToolchain = Join-Path $VcpkgRoot "scripts\buildsystems\vcpkg.cmake"
$VcpkgInstalled = Join-Path $VcpkgRoot "installed\$VcpkgTriplet"
$VcpkgBin = Join-Path $VcpkgInstalled "bin"

Invoke-Step "Install vcpkg dependencies" {
    Invoke-Native (Join-Path $VcpkgRoot "vcpkg.exe") install `
        "boost-assign:${VcpkgTriplet}" `
        "boost-filesystem:${VcpkgTriplet}" `
        "boost-serialization:${VcpkgTriplet}" `
        "boost-thread:${VcpkgTriplet}" `
        "boost-uuid:${VcpkgTriplet}" `
        "boost-graph:${VcpkgTriplet}" `
        "boost-program-options:${VcpkgTriplet}" `
        "boost-test:${VcpkgTriplet}" `
        "libxml2:${VcpkgTriplet}"
}

Invoke-Step "Configure log4cpp" {
    Invoke-Native cmake -S $Log4cppSource -B $Log4cppBuild -G $Generator -A $Platform `
        -DCMAKE_INSTALL_PREFIX="$Prefix" `
        -DCMAKE_BUILD_TYPE=Release
}

Invoke-Step "Install log4cpp" {
    Invoke-Native cmake --build $Log4cppBuild --config Release --target INSTALL --parallel 4
}

Invoke-Step "Configure RTT" {
    Invoke-Native cmake -S $RttSource -B $RttBuild -G $Generator -A $Platform `
        -DCMAKE_TOOLCHAIN_FILE="$VcpkgToolchain" `
        -DCMAKE_PREFIX_PATH="$Prefix;$VcpkgInstalled" `
        -DCMAKE_INSTALL_PREFIX="$Prefix" `
        -DOROCOS_TARGET=win32 `
        -DENABLE_CORBA=OFF `
        -DENABLE_TESTS=OFF `
        -DBUILD_TESTING=OFF `
        -DBUILD_DOCS=OFF `
        -DOROBLD_FORCE_TINY_DEMARSHALLER=ON `
        -DPLUGINS_ENABLE=ON `
        -DPLUGINS_ENABLE_MARSHALLING=ON `
        -DPLUGINS_ENABLE_TYPEKIT=ON `
        -DPLUGINS_ENABLE_SCRIPTING=ON `
        -DORO_OS_USE_BOOST_THREAD=ON `
        -DCMAKE_BUILD_TYPE=Release
}

Invoke-Step "Install RTT" {
    Invoke-Native cmake --build $RttBuild --config Release --target INSTALL --parallel 4
}

Invoke-Step "Configure OCL" {
    Invoke-Native cmake -S $OclSource -B $OclBuild -G $Generator -A $Platform `
        -DCMAKE_TOOLCHAIN_FILE="$VcpkgToolchain" `
        -DCMAKE_PREFIX_PATH="$Prefix;$VcpkgInstalled" `
        -DCMAKE_INSTALL_PREFIX="$Prefix" `
        -DOROCOS_TARGET=win32 `
        -DENABLE_CORBA=OFF `
        -DBUILD_TESTING=OFF `
        -DBUILD_TESTS=OFF `
        -DBUILD_DOCS=OFF `
        -DBUILD_TASKBROWSER=ON `
        -DBUILD_DEPLOYMENT=ON `
        -DBUILD_REPORTING=ON `
        -DBUILD_REPORTING_NETCDF=OFF `
        -DBUILD_LUA_RTT=OFF `
        -DBUILD_TIMER=ON `
        -DBUILD_LOGGING=OFF `
        -DLOG4CPP_ROOT="$Prefix" `
        -DCMAKE_BUILD_TYPE=Release
}

Invoke-Step "Build OCL deployer tools" {
    Invoke-Native cmake --build $OclBuild --config Release --target deployer --parallel 4
    Invoke-Native cmake --build $OclBuild --config Release --target rttscript --parallel 4
}

Invoke-Step "Install OCL" {
    Invoke-Native cmake --build $OclBuild --config Release --target INSTALL --parallel 4
}

Invoke-Step "Validate Windows prefix" {
    $requiredArtifacts = @(
        "bin\orocos-rtt-win32.dll",
        "bin\deployer-win32.exe",
        "bin\rttscript-win32.exe",
        "lib\orocos-log4cpp.lib",
        "lib\orocos\win32\plugins\rtt-scripting-win32.dll",
        "lib\orocos\win32\types\rtt-typekit-win32.dll"
    )

    foreach ($artifact in $requiredArtifacts) {
        $path = Join-Path $Prefix $artifact
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing expected artifact: $path"
        }
    }

    $pathEntries = @(
        (Join-Path $Prefix "bin"),
        (Join-Path $Prefix "lib"),
        (Join-Path $Prefix "lib\orocos\win32\ocl"),
        (Join-Path $Prefix "lib\orocos\win32\ocl\plugins"),
        (Join-Path $Prefix "lib\orocos\win32\ocl\types"),
        (Join-Path $Prefix "lib\orocos\win32\plugins"),
        (Join-Path $Prefix "lib\orocos\win32\types"),
        $VcpkgBin
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $componentPathEntries = @(
        (Join-Path $Prefix "lib\orocos\win32\ocl"),
        (Join-Path $Prefix "lib\orocos\win32\ocl\plugins"),
        (Join-Path $Prefix "lib\orocos\win32\plugins")
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $env:OROCOS_PREFIX = $Prefix
    $env:OROCOS_TARGET = "win32"
    $env:PATH = ($pathEntries -join ";") + ";" + $env:PATH
    $env:RTT_COMPONENT_PATH = $componentPathEntries -join ";"

    $deployerVersionOutput = & (Join-Path $Prefix "bin\deployer-win32.exe") --version 2>&1
    if ($deployerVersionOutput -notmatch "OROCOS Toolchain version") {
        throw "deployer-win32.exe --version did not print the expected version output"
    }

    Invoke-Native (Join-Path $Prefix "bin\deployer-win32.exe") --check --no-consolelog
    Invoke-Native (Join-Path $Prefix "bin\rttscript-win32.exe") --check --no-consolelog
}
