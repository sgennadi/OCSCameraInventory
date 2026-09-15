param(
    [ValidateSet("Both", "x86", "x64")]
    [string]$Architecture = "Both"
)

$ErrorActionPreference = "Stop"

function Get-PeMachine {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $stream = [System.IO.File]::OpenRead($Path)

    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset

        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Invalid PE signature: $Path"
        }

        return $reader.ReadUInt16()
    }
    finally {
        $stream.Dispose()
    }
}

Write-Host "OCSCameraInventory-Universal - Windows DLL build"
Write-Host "Visual Studio 2026 / MSVC v145"
Write-Host "Targets: x86 and/or x64"
Write-Host "Native ARM64 is not a supported target in this project."
Write-Host "No MFC or OCS source tree is required."
Write-Host ""

$vswhereCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
    "$env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe"
)

$vswhere = $vswhereCandidates |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if (-not $vswhere) {
    throw "vswhere.exe was not found. Install Visual Studio 2026 or Build Tools 2026."
}

$vsInstall = & $vswhere `
    -latest `
    -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath |
    Select-Object -First 1

$vsVersionText = & $vswhere `
    -latest `
    -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationVersion |
    Select-Object -First 1

if (-not $vsInstall -or -not $vsVersionText) {
    throw @"
Visual Studio 2026 C++ x86/x64 build tools were not found.

Open Visual Studio Installer -> Modify and install:
- Visual Studio 2026 or Build Tools 2026
- Desktop development with C++
- MSVC v145 x86/x64 build tools
- Windows 10/11 SDK

MFC is not required for this project.
"@
}

try {
    $vsVersion = [Version]$vsVersionText
}
catch {
    throw "Could not parse Visual Studio version: $vsVersionText"
}

if ($vsVersion.Major -lt 18) {
    throw "Visual Studio 2026 (18.x) is required. Found version $vsVersionText at $vsInstall."
}

$msbuild = Join-Path $vsInstall "MSBuild\Current\Bin\MSBuild.exe"

if (-not (Test-Path $msbuild)) {
    throw "MSBuild.exe was not found in the Visual Studio 2026 installation: $msbuild"
}

$project = Join-Path $PSScriptRoot "src\OCSCameraInventory.vcxproj"

if (-not (Test-Path $project)) {
    throw "Project not found: $project"
}

Write-Host "Visual Studio: $vsInstall"
Write-Host "Visual Studio version: $vsVersionText"
Write-Host "Platform toolset: v145"
Write-Host "MSBuild: $msbuild"
Write-Host "Project: $project"
Write-Host ""

$targets = @()

switch ($Architecture) {
    "Both" {
        $targets += [PSCustomObject]@{
            Platform = "Win32"
            Folder = "x86"
            Machine = 0x014C
        }
        $targets += [PSCustomObject]@{
            Platform = "x64"
            Folder = "x64"
            Machine = 0x8664
        }
    }
    "x86" {
        $targets += [PSCustomObject]@{
            Platform = "Win32"
            Folder = "x86"
            Machine = 0x014C
        }
    }
    "x64" {
        $targets += [PSCustomObject]@{
            Platform = "x64"
            Folder = "x64"
            Machine = 0x8664
        }
    }
}

foreach ($target in $targets) {
    $platform = $target.Platform
    $outputFolder = Join-Path $PSScriptRoot ("build\{0}" -f $target.Folder)
    $objFolder = Join-Path $PSScriptRoot ("obj\{0}" -f $target.Folder)

    if (Test-Path $outputFolder) {
        Remove-Item $outputFolder -Recurse -Force
    }

    if (Test-Path $objFolder) {
        Remove-Item $objFolder -Recurse -Force
    }

    Write-Host "============================================================"
    Write-Host "Building Release|$platform with v145"
    Write-Host "============================================================"

    & $msbuild `
        $project `
        /m `
        /t:Rebuild `
        /p:Configuration=Release `
        /p:Platform=$platform `
        /p:PlatformToolset=v145 `
        /p:WindowsTargetPlatformVersion=10.0

    if ($LASTEXITCODE -ne 0) {
        throw "Build failed for $platform with exit code $LASTEXITCODE. Verify that MSVC v145 x86/x64 build tools are installed."
    }

    $dll = Join-Path $outputFolder "OCSCameraInventory.dll"

    if (-not (Test-Path $dll)) {
        throw "Build reported success but DLL was not found: $dll"
    }

    $machine = Get-PeMachine -Path $dll

    if ($machine -ne $target.Machine) {
        throw ("Unexpected PE machine for {0}: 0x{1:X4}" -f $dll, $machine)
    }

    $item = Get-Item $dll
    Write-Host "SUCCESS: $dll"
    Write-Host ("Size: {0} bytes" -f $item.Length)
    Write-Host ""
}

Write-Host "Build finished successfully with Visual Studio 2026 / v145."
