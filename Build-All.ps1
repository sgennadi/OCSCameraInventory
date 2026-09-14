param(
    [ValidateSet("Both","x86","x64")]
    [string]$Architecture = "Both"
)

$ErrorActionPreference = "Stop"

Write-Host "OCS Camera Inventory - Universal DLL build"
Write-Host "No MFC / no OCS source tree required."
Write-Host ""

$vswhereCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
    "$env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe"
)

$vswhere = $vswhereCandidates |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if (-not $vswhere) {
    throw "vswhere.exe was not found."
}

$msbuild = & $vswhere `
    -latest `
    -products * `
    -requires Microsoft.Component.MSBuild `
    -find "MSBuild\**\Bin\MSBuild.exe" |
    Select-Object -First 1

if (-not $msbuild) {
    throw "MSBuild was not found."
}

$vsInstall = & $vswhere `
    -latest `
    -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath |
    Select-Object -First 1

if (-not $vsInstall) {
    throw @"
Visual C++ x86/x64 build tools were not found.

Open Visual Studio Installer -> Modify and install:
Desktop development with C++

MFC is NOT required for this version of the plugin.
"@
}

$project = Join-Path $PSScriptRoot "src\OCSCameraInventory.vcxproj"

if (-not (Test-Path $project)) {
    throw "Project not found: $project"
}

Write-Host "Visual Studio: $vsInstall"
Write-Host "MSBuild: $msbuild"
Write-Host ""

$targets = @()

switch ($Architecture) {
    "Both" {
        $targets += "Win32"
        $targets += "x64"
    }
    "x86" {
        $targets += "Win32"
    }
    "x64" {
        $targets += "x64"
    }
}

foreach ($platform in $targets) {
    Write-Host "============================================================"
    Write-Host "Building Release|$platform"
    Write-Host "============================================================"

    & $msbuild `
        $project `
        /m `
        /t:Rebuild `
        /p:Configuration=Release `
        /p:Platform=$platform `
        /p:PlatformToolset=v143 `
        /p:WindowsTargetPlatformVersion=10.0

    if ($LASTEXITCODE -ne 0) {
        throw "Build failed for $platform with exit code $LASTEXITCODE."
    }
}

$x86Dll = Join-Path $PSScriptRoot "build\x86\OCSCameraInventory.dll"
$x64Dll = Join-Path $PSScriptRoot "build\x64\OCSCameraInventory.dll"

Write-Host ""
Write-Host "Build finished."

if (Test-Path $x86Dll) {
    Write-Host "x86: $x86Dll"
}

if (Test-Path $x64Dll) {
    Write-Host "x64: $x64Dll"
}
