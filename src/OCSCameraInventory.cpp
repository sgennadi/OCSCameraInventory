// OCSCameraInventory.cpp
// Universal native DLL plugin for OCS Inventory Windows Agent.
//
// Design goals:
// - No PowerShell/VBS inventory plugin.
// - No Registry Query.
// - No OCS/MFC headers at build time.
// - No MFC runtime dependency from this DLL.
// - Static C/C++ runtime (/MT).
// - Separate x86 and x64 DLLs in one package.
// - Runtime resolution of the small, stable OCS C++ XML API.
//
// Verified OCS public plugin/XML interfaces:
// - OCS Windows Agent 2.6.0.1
// - OCS Windows Agent 2.9.1.0
// - OCS Windows Agent 2.11.0.1
//
// Inventory output uses the standard INPUTS section:
// TYPE          = OCS_CAMERA
// MANUFACTURER  = manufacturer
// CAPTION       = friendly camera name
// DESCRIPTION   = full PnP instance ID
// INTERFACE     = VID_xxxx&PID_xxxx
// POINTTYPE     = Camera; Class=...; Service=...

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <psapi.h>
#include <dbghelp.h>

#include <algorithm>
#include <cwctype>
#include <string>
#include <vector>

#pragma comment(lib, "setupapi.lib")
#pragma comment(lib, "psapi.lib")
#pragma comment(lib, "dbghelp.lib")

static const int PLUGIN_OK = 0;
static const size_t OCS_TEXT_LIMIT = 250;

#ifdef _M_IX86
#define OCS_THISCALL __thiscall
#else
#define OCS_THISCALL
#endif

typedef void* (OCS_THISCALL *PFN_GET_XML_CONTENT)(void* requestObject);
typedef void* (OCS_THISCALL *PFN_ADD_ELEM)(
    void* markupObject,
    const wchar_t* name,
    const wchar_t* value);
typedef void* (OCS_THISCALL *PFN_ADD_CHILD_ELEM)(
    void* markupObject,
    const wchar_t* name,
    const wchar_t* value);

struct OcsXmlApi
{
    PFN_GET_XML_CONTENT getXmlPointerContent;
    PFN_ADD_ELEM addElem;
    PFN_ADD_CHILD_ELEM addChildElem;
    HMODULE sourceModule;

    OcsXmlApi()
        : getXmlPointerContent(NULL),
          addElem(NULL),
          addChildElem(NULL),
          sourceModule(NULL)
    {
    }

    bool Ready() const
    {
        return getXmlPointerContent != NULL &&
               addElem != NULL &&
               addChildElem != NULL;
    }
};

static OcsXmlApi g_ocsApi;

static std::wstring ToLower(const std::wstring& value)
{
    std::wstring result(value);
    std::transform(
        result.begin(),
        result.end(),
        result.begin(),
        [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
    return result;
}

static std::wstring ToUpper(const std::wstring& value)
{
    std::wstring result(value);
    std::transform(
        result.begin(),
        result.end(),
        result.begin(),
        [](wchar_t c) { return static_cast<wchar_t>(towupper(c)); });
    return result;
}

static bool EqualsNoCase(
    const std::wstring& left,
    const wchar_t* right)
{
    return _wcsicmp(left.c_str(), right) == 0;
}

static bool ContainsNoCase(
    const std::wstring& value,
    const wchar_t* text)
{
    return ToLower(value).find(ToLower(text)) != std::wstring::npos;
}

static bool StartsWithNoCase(
    const std::wstring& value,
    const wchar_t* prefix)
{
    const std::wstring loweredValue = ToLower(value);
    const std::wstring loweredPrefix = ToLower(prefix);

    if (loweredValue.size() < loweredPrefix.size())
        return false;

    return loweredValue.compare(
        0,
        loweredPrefix.size(),
        loweredPrefix) == 0;
}

static std::wstring LimitText(const std::wstring& value)
{
    if (value.size() <= OCS_TEXT_LIMIT)
        return value;

    return value.substr(0, OCS_TEXT_LIMIT);
}

static bool GetDevicePropertyString(
    HDEVINFO deviceInfoSet,
    PSP_DEVINFO_DATA deviceInfoData,
    DWORD property,
    std::wstring& value)
{
    value.clear();

    DWORD propertyType = 0;
    DWORD requiredBytes = 0;

    SetupDiGetDeviceRegistryPropertyW(
        deviceInfoSet,
        deviceInfoData,
        property,
        &propertyType,
        NULL,
        0,
        &requiredBytes);

    if (requiredBytes == 0)
        return false;

    std::vector<BYTE> buffer(requiredBytes + sizeof(wchar_t) * 2, 0);

    if (!SetupDiGetDeviceRegistryPropertyW(
            deviceInfoSet,
            deviceInfoData,
            property,
            &propertyType,
            &buffer[0],
            static_cast<DWORD>(buffer.size()),
            &requiredBytes))
    {
        return false;
    }

    const wchar_t* text =
        reinterpret_cast<const wchar_t*>(&buffer[0]);

    value.assign(text);
    return !value.empty();
}

static bool GetDeviceInstanceId(
    HDEVINFO deviceInfoSet,
    PSP_DEVINFO_DATA deviceInfoData,
    std::wstring& value)
{
    value.clear();

    DWORD requiredChars = 0;

    SetupDiGetDeviceInstanceIdW(
        deviceInfoSet,
        deviceInfoData,
        NULL,
        0,
        &requiredChars);

    if (requiredChars == 0)
        return false;

    std::vector<wchar_t> buffer(requiredChars + 2, 0);

    if (!SetupDiGetDeviceInstanceIdW(
            deviceInfoSet,
            deviceInfoData,
            &buffer[0],
            static_cast<DWORD>(buffer.size()),
            &requiredChars))
    {
        return false;
    }

    value.assign(&buffer[0]);
    return !value.empty();
}

static std::wstring ExtractUsbId(
    const std::wstring& instanceId)
{
    const std::wstring upper = ToUpper(instanceId);

    const size_t vidPos = upper.find(L"VID_");
    const size_t pidPos = upper.find(L"PID_");

    if (vidPos == std::wstring::npos ||
        pidPos == std::wstring::npos ||
        vidPos + 8 > upper.size() ||
        pidPos + 8 > upper.size())
    {
        return L"USB";
    }

    return L"VID_" + upper.substr(vidPos + 4, 4) +
           L"&PID_" + upper.substr(pidPos + 4, 4);
}

static bool IsPhysicalUsbCamera(
    const std::wstring& instanceId,
    const std::wstring& className,
    const std::wstring& serviceName,
    const std::wstring& friendlyName)
{
    // Only physical USB PnP devices.
    if (!StartsWithNoCase(instanceId, L"USB\\"))
        return false;

    // Scanners and printer imaging interfaces.
    if (EqualsNoCase(serviceName, L"usbscan") ||
        EqualsNoCase(serviceName, L"stillcam"))
    {
        return false;
    }

    // Remote/virtual camera bus.
    if (ContainsNoCase(
            friendlyName,
            L"remote desktop camera bus") ||
        ContainsNoCase(
            instanceId,
            L"RDCAMERA_BUS"))
    {
        return false;
    }

    const bool cameraClass =
        EqualsNoCase(className, L"Camera");

    const bool usbVideoService =
        EqualsNoCase(serviceName, L"usbvideo");

    const bool cameraLikeName =
        ContainsNoCase(friendlyName, L"camera") ||
        ContainsNoCase(friendlyName, L"webcam") ||
        ContainsNoCase(friendlyName, L"usb video") ||
        ContainsNoCase(friendlyName, L"uvc");

    const bool legacyImageCamera =
        EqualsNoCase(className, L"Image") &&
        (usbVideoService || cameraLikeName);

    return cameraClass ||
           usbVideoService ||
           legacyImageCamera;
}

static bool IsTextXmlOverload(
    const char* undecoratedName,
    const char* methodName)
{
    if (undecoratedName == NULL)
        return false;

    std::string text(undecoratedName);

    if (text.find("CMarkup::") == std::string::npos ||
        text.find(methodName) == std::string::npos)
    {
        return false;
    }

    // Reject the overload whose second argument is LONG.
    if (text.find(",long)") != std::string::npos ||
        text.find(", long)") != std::string::npos)
    {
        return false;
    }

    // The LPCTSTR overload contains two pointer arguments.
    // Different MSVC versions can demangle TCHAR as wchar_t or unsigned short.
    const size_t open = text.find('(');
    const size_t close = text.rfind(')');

    if (open == std::string::npos ||
        close == std::string::npos ||
        close <= open)
    {
        return false;
    }

    const std::string args =
        text.substr(open + 1, close - open - 1);

    size_t stars = 0;
    for (size_t i = 0; i < args.size(); ++i)
    {
        if (args[i] == '*')
            ++stars;
    }

    return stars >= 2;
}

static bool ResolveFromModule(
    HMODULE module,
    OcsXmlApi& api)
{
    if (module == NULL)
        return false;

    const BYTE* base =
        reinterpret_cast<const BYTE*>(module);

    const IMAGE_DOS_HEADER* dos =
        reinterpret_cast<const IMAGE_DOS_HEADER*>(base);

    if (dos->e_magic != IMAGE_DOS_SIGNATURE)
        return false;

    const IMAGE_NT_HEADERS* nt =
        reinterpret_cast<const IMAGE_NT_HEADERS*>(
            base + dos->e_lfanew);

    if (nt->Signature != IMAGE_NT_SIGNATURE)
        return false;

    const IMAGE_DATA_DIRECTORY& exportDirectoryInfo =
        nt->OptionalHeader.DataDirectory[
            IMAGE_DIRECTORY_ENTRY_EXPORT];

    if (exportDirectoryInfo.VirtualAddress == 0)
        return false;

    const IMAGE_EXPORT_DIRECTORY* exports =
        reinterpret_cast<const IMAGE_EXPORT_DIRECTORY*>(
            base + exportDirectoryInfo.VirtualAddress);

    const DWORD* nameRvas =
        reinterpret_cast<const DWORD*>(
            base + exports->AddressOfNames);

    for (DWORD i = 0;
         i < exports->NumberOfNames;
         ++i)
    {
        const char* exportName =
            reinterpret_cast<const char*>(
                base + nameRvas[i]);

        if (exportName == NULL)
            continue;

        const bool maybeGetContent =
            strstr(
                exportName,
                "getXmlPointerContent") != NULL;

        const bool maybeAddElem =
            strstr(
                exportName,
                "AddElem") != NULL;

        const bool maybeAddChild =
            strstr(
                exportName,
                "AddChildElem") != NULL;

        if (!maybeGetContent &&
            !maybeAddElem &&
            !maybeAddChild)
        {
            continue;
        }

        char undecorated[2048] = { 0 };

        if (UnDecorateSymbolName(
                exportName,
                undecorated,
                static_cast<DWORD>(sizeof(undecorated)),
                UNDNAME_COMPLETE) == 0)
        {
            continue;
        }

        FARPROC address =
            GetProcAddress(module, exportName);

        if (address == NULL)
            continue;

        const std::string pretty(undecorated);

        if (api.getXmlPointerContent == NULL &&
            pretty.find(
                "CRequestAbstract::getXmlPointerContent(") !=
                std::string::npos)
        {
            api.getXmlPointerContent =
                reinterpret_cast<PFN_GET_XML_CONTENT>(
                    address);
        }
        else if (api.addChildElem == NULL &&
                 IsTextXmlOverload(
                     undecorated,
                     "AddChildElem("))
        {
            api.addChildElem =
                reinterpret_cast<PFN_ADD_CHILD_ELEM>(
                    address);
        }
        else if (api.addElem == NULL &&
                 pretty.find("AddChildElem") ==
                     std::string::npos &&
                 IsTextXmlOverload(
                     undecorated,
                     "AddElem("))
        {
            api.addElem =
                reinterpret_cast<PFN_ADD_ELEM>(
                    address);
        }
    }

    if (api.Ready())
    {
        api.sourceModule = module;
        return true;
    }

    return false;
}

static bool ResolveOcsXmlApi()
{
    if (g_ocsApi.Ready())
        return true;

    HMODULE modules[1024] = { 0 };
    DWORD bytesNeeded = 0;

    if (!EnumProcessModules(
            GetCurrentProcess(),
            modules,
            sizeof(modules),
            &bytesNeeded))
    {
        return false;
    }

    const DWORD moduleCount =
        min(
            static_cast<DWORD>(
                sizeof(modules) /
                sizeof(modules[0])),
            bytesNeeded /
                static_cast<DWORD>(
                    sizeof(HMODULE)));

    for (DWORD i = 0;
         i < moduleCount;
         ++i)
    {
        OcsXmlApi candidate;

        if (ResolveFromModule(
                modules[i],
                candidate))
        {
            g_ocsApi = candidate;
            return true;
        }
    }

    return false;
}

static bool AddInputCamera(
    void* inventoryRequest,
    const std::wstring& manufacturer,
    const std::wstring& caption,
    const std::wstring& instanceId,
    const std::wstring& className,
    const std::wstring& serviceName)
{
    if (!ResolveOcsXmlApi())
        return false;

    void* markup =
        g_ocsApi.getXmlPointerContent(
            inventoryRequest);

    if (markup == NULL)
        return false;

    // AddElem changes current position to the new INPUTS node.
    if (g_ocsApi.addElem(
            markup,
            L"INPUTS",
            NULL) == NULL)
    {
        return false;
    }

    const std::wstring type =
        L"OCS_CAMERA";

    const std::wstring safeManufacturer =
        LimitText(
            manufacturer.empty()
                ? L"Unknown"
                : manufacturer);

    const std::wstring safeCaption =
        LimitText(
            caption.empty()
                ? L"USB Camera"
                : caption);

    const std::wstring safeInstanceId =
        LimitText(instanceId);

    const std::wstring interfaceText =
        LimitText(
            ExtractUsbId(instanceId));

    const std::wstring pointType =
        LimitText(
            L"Camera; Class=" +
            className +
            L"; Service=" +
            serviceName);

    if (g_ocsApi.addChildElem(
            markup,
            L"TYPE",
            type.c_str()) == NULL)
        return false;

    if (g_ocsApi.addChildElem(
            markup,
            L"MANUFACTURER",
            safeManufacturer.c_str()) == NULL)
        return false;

    if (g_ocsApi.addChildElem(
            markup,
            L"CAPTION",
            safeCaption.c_str()) == NULL)
        return false;

    if (g_ocsApi.addChildElem(
            markup,
            L"DESCRIPTION",
            safeInstanceId.c_str()) == NULL)
        return false;

    if (g_ocsApi.addChildElem(
            markup,
            L"INTERFACE",
            interfaceText.c_str()) == NULL)
        return false;

    if (g_ocsApi.addChildElem(
            markup,
            L"POINTTYPE",
            pointType.c_str()) == NULL)
        return false;

    return true;
}

static int InventoryCameras(
    void* inventoryRequest)
{
    if (inventoryRequest == NULL)
        return 10;

    if (!ResolveOcsXmlApi())
        return 11;

    HDEVINFO deviceInfoSet =
        SetupDiGetClassDevsW(
            NULL,
            NULL,
            NULL,
            DIGCF_ALLCLASSES |
            DIGCF_PRESENT);

    if (deviceInfoSet ==
        INVALID_HANDLE_VALUE)
    {
        return 12;
    }

    SP_DEVINFO_DATA deviceInfoData;
    ZeroMemory(
        &deviceInfoData,
        sizeof(deviceInfoData));
    deviceInfoData.cbSize =
        sizeof(deviceInfoData);

    DWORD index = 0;
    int result = PLUGIN_OK;

    while (SetupDiEnumDeviceInfo(
        deviceInfoSet,
        index,
        &deviceInfoData))
    {
        ++index;

        std::wstring instanceId;
        std::wstring className;
        std::wstring serviceName;
        std::wstring friendlyName;
        std::wstring deviceDescription;
        std::wstring manufacturer;

        if (!GetDeviceInstanceId(
                deviceInfoSet,
                &deviceInfoData,
                instanceId))
        {
            continue;
        }

        GetDevicePropertyString(
            deviceInfoSet,
            &deviceInfoData,
            SPDRP_CLASS,
            className);

        GetDevicePropertyString(
            deviceInfoSet,
            &deviceInfoData,
            SPDRP_SERVICE,
            serviceName);

        GetDevicePropertyString(
            deviceInfoSet,
            &deviceInfoData,
            SPDRP_FRIENDLYNAME,
            friendlyName);

        GetDevicePropertyString(
            deviceInfoSet,
            &deviceInfoData,
            SPDRP_DEVICEDESC,
            deviceDescription);

        GetDevicePropertyString(
            deviceInfoSet,
            &deviceInfoData,
            SPDRP_MFG,
            manufacturer);

        if (friendlyName.empty())
            friendlyName =
                deviceDescription;

        if (!IsPhysicalUsbCamera(
                instanceId,
                className,
                serviceName,
                friendlyName))
        {
            continue;
        }

        if (!AddInputCamera(
                inventoryRequest,
                manufacturer,
                friendlyName,
                instanceId,
                className,
                serviceName))
        {
            result = 13;
            break;
        }
    }

    SetupDiDestroyDeviceInfoList(
        deviceInfoSet);

    return result;
}

// OCS looks up these exact hook names with GetProcAddress.
// Keep C linkage and standard C calling convention.

extern "C" __declspec(dllexport)
int OCS_CALL_START_EXPORTED()
{
    // Resolve early. If the OCS XML module is not yet loaded,
    // the inventory hook will retry.
    ResolveOcsXmlApi();
    return PLUGIN_OK;
}

extern "C" __declspec(dllexport)
int OCS_CALL_PROLOGWRITE_EXPORTED(
    void* /*prologRequest*/)
{
    return PLUGIN_OK;
}

extern "C" __declspec(dllexport)
int OCS_CALL_PROLOGRESP_EXPORTED(
    void* /*prologResponse*/)
{
    return PLUGIN_OK;
}

extern "C" __declspec(dllexport)
int OCS_CALL_INVENTORY_EXPORTED(
    void* inventoryRequest)
{
    return InventoryCameras(
        inventoryRequest);
}

extern "C" __declspec(dllexport)
int OCS_CALL_END_EXPORTED(
    void* /*inventoryResponse*/)
{
    return PLUGIN_OK;
}

extern "C" __declspec(dllexport)
int OCS_CALL_CLEAN_EXPORTED()
{
    return PLUGIN_OK;
}
