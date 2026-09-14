param(
    [switch]$ForceInventory
)

$ErrorActionPreference = "Stop"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Get-PeArchitecture {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )

    try {
        $reader = New-Object System.IO.BinaryReader($stream)

        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()

        $stream.Position = $peOffset
        $signature = $reader.ReadUInt32()

        if ($signature -ne 0x00004550) {
            throw "Invalid PE signature: $Path"
        }

        $machine = $reader.ReadUInt16()

        switch ($machine) {
            0x014C { return "x86" }
            0x8664 { return "x64" }
            default {
                throw ("Unsupported PE machine 0x{0:X4}: {1}" -f $machine, $Path)
            }
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-OcsAgentExe {
    $serviceCandidates = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PathName -match "OCSInventory" -or
            $_.DisplayName -match "OCS.*Inventory"
        }

    foreach ($service in $serviceCandidates) {
        $path = $service.PathName

        if ($path -match '^\s*"([^"]+OCSInventory\.exe)"') {
            if (Test-Path $matches[1]) {
                return $matches[1]
            }
        }

        if ($path -match '^\s*([^\s]+.*?OCSInventory\.exe)') {
            $candidate = $matches[1].Trim('"')

            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    $common = @(
        "${env:ProgramFiles(x86)}\OCS Inventory Agent\OCSInventory.exe",
        "$env:ProgramFiles\OCS Inventory Agent\OCSInventory.exe"
    ) | Select-Object -Unique

    foreach ($candidate in $common) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    throw "OCSInventory.exe was not found."
}

if (-not (Test-Administrator)) {
    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`""
    )

    if ($ForceInventory) {
        $argumentList += "-ForceInventory"
    }

    Start-Process powershell.exe `
        -ArgumentList $argumentList `
        -Verb RunAs

    exit
}

$ocsExe = Get-OcsAgentExe
$ocsRoot = Split-Path $ocsExe -Parent
$plugins = Join-Path $ocsRoot "plugins"

$architecture = Get-PeArchitecture -Path $ocsExe
$versionInfo = (Get-Item $ocsExe).VersionInfo
$agentVersion = $versionInfo.ProductVersion

$dll = Join-Path `
    $PSScriptRoot `
    ("build\{0}\OCSCameraInventory.dll" -f $architecture)

if (-not (Test-Path $dll)) {
    throw @"
The $architecture plugin DLL was not found:
$dll

Run Build-All.ps1 first.
"@
}

Write-Host "OCS Agent:"
Write-Host "  EXE: $ocsExe"
Write-Host "  Version: $agentVersion"
Write-Host "  Architecture: $architecture"
Write-Host ""

New-Item -ItemType Directory `
    -Path $plugins `
    -Force |
    Out-Null

$services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
    Where-Object {
        $_.PathName -match [regex]::Escape($ocsRoot)
    }

$runningServices = @()

foreach ($service in $services) {
    if ($service.State -eq "Running") {
        $runningServices += $service.Name

        Stop-Service `
            -Name $service.Name `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

Get-Process OCSInventory `
    -ErrorAction SilentlyContinue |
    Stop-Process `
        -Force `
        -ErrorAction SilentlyContinue

$destination = Join-Path `
    $plugins `
    "OCSCameraInventory.dll"

Copy-Item `
    $dll `
    $destination `
    -Force

foreach ($serviceName in $runningServices) {
    Start-Service `
        -Name $serviceName `
        -ErrorAction SilentlyContinue
}

Write-Host "Installed:"
Write-Host "  $destination"
Write-Host ""

if ($ForceInventory) {
    Write-Host "Forcing OCS inventory..."

    & $ocsExe /force /debug=2

    Start-Sleep -Seconds 35

    $log = Join-Path `
        $env:ProgramData `
        "OCS Inventory NG\Agent\ocsinventory.log"

    if (Test-Path $log) {
        Select-String `
            -Path $log `
            -Pattern "DLL PLUGIN|OCSCameraInventory" |
            Select-Object -Last 30
    }
}
