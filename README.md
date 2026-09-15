# OCSCameraInventory-Universal

[![Build Windows DLLs](https://github.com/sgennadi/OCSCameraInventory/actions/workflows/build-windows.yml/badge.svg)](https://github.com/sgennadi/OCSCameraInventory/actions/workflows/build-windows.yml)

Universal native camera inventory plugin for **OCS Inventory NG Windows Agent**.

The plugin inventories present physical USB cameras/webcams and adds them to the standard OCS `INPUTS` inventory section with:

```text
TYPE = OCS_CAMERA
```

## Supported platforms

| Platform / OCS Agent process | Status | DLL |
|---|---|---|
| Windows x86 | Supported | `build/x86/OCSCameraInventory.dll` |
| Windows x64 | Supported | `build/x64/OCSCameraInventory.dll` |
| Windows ARM64 running an x86 OCS Agent | Supported through Windows emulation | x86 DLL |
| Windows ARM64 running an x64 OCS Agent | Supported through Windows emulation | x64 DLL |
| Native ARM64 OCS Agent | Not published/tested | No ARM64 DLL |
| Linux / OCS UnixAgent | Windows DLL is not compatible | Separate Linux/UnixAgent plugin required |

**Universal** in this repository means one Windows project/package that supports both x86 and x64 OCS Inventory Agent installations.

The DLL architecture must match the architecture of `OCSInventory.exe`, not the architecture of Windows itself. `Install-Universal.ps1` reads the PE header of the installed agent and chooses the correct DLL automatically.

The upstream OCS Windows Agent plugin project exposes Win32 and x64 configurations, not a native ARM64 plugin target. For that reason this project does not claim native ARM64 plugin compatibility. If OCS later provides a native ARM64 Windows Agent with a compatible plugin ABI, ARM64 can be evaluated separately.

A Windows `.dll` cannot be loaded by the OCS UnixAgent on Linux. Linux support needs a separate implementation using the UnixAgent plugin/module mechanism and Linux camera interfaces such as `udev`, `/dev/video*`, V4L2 and/or `lsusb`.

## What the plugin collects

Each detected camera is written as an `INPUTS` record similar to:

```text
TYPE          OCS_CAMERA
MANUFACTURER  Logitech
CAPTION       Logitech HD Pro Webcam C920
DESCRIPTION   USB\VID_046D&PID_082D&MI_00\...
INTERFACE     VID_046D&PID_082D
POINTTYPE     Camera; Class=Camera; Service=usbvideo
```

The plugin uses Windows SetupAPI to enumerate present USB devices. It accepts camera-class / `usbvideo` devices and excludes common non-camera imaging devices such as scanners and Remote Desktop Camera Bus devices.

## Automatic GitHub build

Git itself does not compile code. **GitHub Actions** does the automatic build.

Workflow:

```text
.github/workflows/build-windows.yml
```

It runs on pushes to `main`, pull requests that change source/build files, and manual `workflow_dispatch` runs. It builds fresh x86 and x64 DLLs and publishes downloadable Actions artifacts:

```text
OCSCameraInventory-Windows-x86
OCSCameraInventory-Windows-x64
OCSCameraInventory-Universal-Windows
```

The universal artifact contains both DLL architectures plus the installer and SQL examples.

> GitHub Actions validates that the project compiles and that each produced PE file has the expected x86/x64 machine type. It does not prove runtime compatibility with every OCS Agent release.

## Local build

Requirements:

- Windows 10/11
- Visual Studio 2022 or Visual Studio Build Tools 2022
- Desktop development with C++
- MSVC v143 x86/x64 build tools
- Windows 10/11 SDK

MFC and the OCS source tree are **not** required to compile this version of the plugin.

Build both architectures:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-All.ps1
```

Or build only one:

```powershell
.\Build-All.ps1 -Architecture x86
.\Build-All.ps1 -Architecture x64
```

Expected output:

```text
build\x86\OCSCameraInventory.dll
build\x64\OCSCameraInventory.dll
```

## Install

Run from an elevated PowerShell console, or allow the script to elevate itself:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Universal.ps1
```

To request an inventory immediately after installation:

```powershell
.\Install-Universal.ps1 -ForceInventory
```

The installer:

- finds the installed `OCSInventory.exe`;
- reads its actual PE architecture;
- selects the matching x86/x64 plugin;
- stops the OCS service/process while replacing the DLL;
- installs `plugins\OCSCameraInventory.dll`;
- restarts services that were running.

A native ARM64 `OCSInventory.exe` is detected explicitly and rejected with a clear message because this repository does not publish a native ARM64 plugin.

## Database

Camera records are stored in the existing OCS `inputs` table. No new database table is required.

### CentOS / MariaDB one-line commands

All examples below prompt for the database root password and use the `ocsweb` database directly.

Show all cameras:

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,h.USERID AS UserName,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId,i.POINTTYPE AS Details FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' ORDER BY h.NAME,i.CAPTION;"
```

Count all cameras:

```bash
mysql -u root -p ocsweb -e "SELECT COUNT(*) AS TotalCameras FROM inputs WHERE TYPE='OCS_CAMERA';"
```

Find Logitech C920 by VID/PID:

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,h.USERID AS UserName,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(CONCAT(COALESCE(i.INTERFACE,''),' ',COALESCE(i.DESCRIPTION,''))) LIKE '%VID_046D%PID_082D%' ORDER BY h.NAME;"
```

Find Logitech C920 by model name:

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(i.CAPTION) LIKE '%C920%' ORDER BY h.NAME;"
```

Find all Logitech cameras:

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,h.USERID AS UserName,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(CONCAT(COALESCE(i.MANUFACTURER,''),' ',COALESCE(i.CAPTION,''),' ',COALESCE(i.DESCRIPTION,''))) LIKE '%LOGITECH%' ORDER BY h.NAME,i.CAPTION;"
```

Find any camera by VID/PID, replacing `XXXX` and `YYYY`:

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,h.USERID AS UserName,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(CONCAT(COALESCE(i.INTERFACE,''),' ',COALESCE(i.DESCRIPTION,''))) LIKE '%VID_XXXX%PID_YYYY%' ORDER BY h.NAME;"
```

For all additional one-line examples — model text search, per-computer search, manufacturer search, computers with multiple cameras, distinct VID/PID values, counts by model and more — see [`CentOS-MySQL-One-Line-Commands.md`](CentOS-MySQL-One-Line-Commands.md).

### SQL-only examples

The same searches are also available as plain SQL in [`queries.sql`](queries.sql).

## Project layout

```text
OCSCameraInventory-Universal/
├── .github/
│   └── workflows/
│       └── build-windows.yml
├── build/
│   ├── x86/OCSCameraInventory.dll
│   └── x64/OCSCameraInventory.dll
├── src/
│   ├── OCSCameraInventory.cpp
│   └── OCSCameraInventory.vcxproj
├── Build-All.ps1
├── Install-Universal.ps1
├── queries.sql
├── CentOS-MySQL-One-Line-Commands.md
├── .gitattributes
├── .gitignore
└── README.md
```

## Implementation note

This version does not link against an OCS version-specific import library. It resolves the small OCS XML API used to add inventory data from modules already loaded inside the OCS Inventory process. The source is intentionally self-contained and links the static MSVC runtime (`/MT`).

The project is Windows-only; no Registry Query, executable PowerShell/VBS inventory plugin, or MFC runtime is required for camera collection.
