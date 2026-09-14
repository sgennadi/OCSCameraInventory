OCS Camera Inventory Universal DLL v3
=====================================

Goal
----
One deployment package for old/new OCS Windows Agent installations and
both x86 and x64 agents.

Important
---------
A single Windows DLL cannot be both x86 and x64.

This package builds:
  build\x86\OCSCameraInventory.dll
  build\x64\OCSCameraInventory.dll

Install-Universal.ps1 reads the PE architecture of the installed
OCSInventory.exe and automatically installs the matching DLL.

Verified OCS API compatibility
------------------------------
The small OCS DLL/XML API used by this plugin has been checked in:

  OCS Windows Agent 2.6.0.1
  OCS Windows Agent 2.9.1.0
  OCS Windows Agent 2.11.0.1

2.11.0.1 is the current public release at the time this package was made.

The relevant public interfaces are unchanged across those versions:
  OCS_CALL_INVENTORY_EXPORTED
  CRequestAbstract::getXmlPointerContent()
  CMarkup::AddElem()
  CMarkup::AddChildElem()

The plugin resolves the OCS C++ XML methods at runtime from the modules
already loaded by OCSInventory.exe. It does not link to an OCS version
specific import library.

Why v3 does not need MFC
------------------------
Earlier source packages built against the official OCS C++ projects,
which required the MFC development components.

v3 does not include OCS/MFC headers and does not build the OCS source
tree. It uses only the Windows SDK plus the normal MSVC compiler.

MFC development components are NOT required.

The plugin is also compiled with the static C/C++ runtime (/MT), reducing
dependencies on the client.

Build
-----
Required on the build PC:
  Visual Studio 2022 / Build Tools
  Desktop development with C++
  Windows 10/11 SDK

Run:

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-All.ps1

Expected output:

  build\x86\OCSCameraInventory.dll
  build\x64\OCSCameraInventory.dll

Install
-------
Run from the package root:

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Universal.ps1 -ForceInventory

The installer:
  - finds OCSInventory.exe
  - reads its actual PE architecture
  - displays agent version and architecture
  - installs the correct x86/x64 DLL
  - restarts the OCS service if required
  - can force inventory and show the DLL plugin log

Old PS1/VBS test plugins are not required.

Inventory
---------
The plugin adds standard INPUTS records:

  TYPE          OCS_CAMERA
  MANUFACTURER  Microsoft / Logitech / Dell / ...
  CAPTION       camera friendly name
  DESCRIPTION   USB\VID_xxxx&PID_xxxx...
  INTERFACE     VID_xxxx&PID_xxxx
  POINTTYPE     Camera; Class=...; Service=...

It excludes:
  usbscan
  StillCam
  Remote Desktop Camera Bus
  non-USB/virtual cameras

Logitech C920:
  VID_046D
  PID_082D

Server changes
--------------
None.

Data goes to the existing OCS "inputs" table.
See queries.sql.
