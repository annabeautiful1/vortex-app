// platform_channel.cpp - Platform Channel Implementation for Windows
#include "platform_channel.h"
#include "mihomo_core.h"

#include <shlobj.h>
#include <shlwapi.h>
#include <wininet.h>
#include <iostream>
#include <fstream>
#include <filesystem>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "wininet.lib")

std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> PlatformChannel::event_sink_;

void PlatformChannel::Register(flutter::FlutterEngine* engine) {
    // Method Channel
    auto method_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        engine->messenger(), "com.vortex.app/core",
        &flutter::StandardMethodCodec::GetInstance());

    method_channel->SetMethodCallHandler(
        [](const flutter::MethodCall<flutter::EncodableValue>& call,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            HandleMethodCall(call, std::move(result));
        });

    // Event Channel
    auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        engine->messenger(), "com.vortex.app/events",
        &flutter::StandardMethodCodec::GetInstance());

    auto handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        [](const flutter::EncodableValue* arguments,
           std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            event_sink_ = std::move(events);

            // Setup callbacks from MihomoCore
            auto& core = MihomoCore::GetInstance();

            core.SetStateCallback([](const std::string& state) {
                SendEvent("vpn_state_changed", flutter::EncodableValue(state));
            });

            core.SetTrafficCallback([](const MihomoCore::TrafficStats& stats) {
                flutter::EncodableMap data;
                data[flutter::EncodableValue("upload")] = flutter::EncodableValue(static_cast<int64_t>(stats.upload));
                data[flutter::EncodableValue("download")] = flutter::EncodableValue(static_cast<int64_t>(stats.download));
                data[flutter::EncodableValue("uploadSpeed")] = flutter::EncodableValue(static_cast<int64_t>(stats.uploadSpeed));
                data[flutter::EncodableValue("downloadSpeed")] = flutter::EncodableValue(static_cast<int64_t>(stats.downloadSpeed));
                SendEvent("traffic_update", flutter::EncodableValue(data));
            });

            core.SetLogCallback([](const std::string& message) {
                SendEvent("log", flutter::EncodableValue(message));
            });

            core.SetErrorCallback([](const std::string& error) {
                SendEvent("error", flutter::EncodableValue(error));
            });

            return nullptr;
        },
        [](const flutter::EncodableValue* arguments)
            -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            event_sink_ = nullptr;

            auto& core = MihomoCore::GetInstance();
            core.SetStateCallback(nullptr);
            core.SetTrafficCallback(nullptr);
            core.SetLogCallback(nullptr);
            core.SetErrorCallback(nullptr);

            return nullptr;
        });

    event_channel->SetStreamHandler(std::move(handler));

    // Initialize MihomoCore
    auto& core = MihomoCore::GetInstance();
    core.Init(GetConfigDirectory());
}

void PlatformChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    const std::string& method = method_call.method_name();
    const auto* arguments = method_call.arguments();
    auto& core = MihomoCore::GetInstance();

    if (method == "startCore") {
        const auto* args = std::get_if<flutter::EncodableMap>(arguments);
        if (args) {
            auto config_it = args->find(flutter::EncodableValue("configPath"));
            if (config_it != args->end()) {
                std::string configPath = std::get<std::string>(config_it->second);
                bool success = core.Start(configPath);
                result->Success(flutter::EncodableValue(success));
                return;
            }
        }
        result->Success(flutter::EncodableValue(false));

    } else if (method == "stopCore") {
        bool success = core.Stop();
        result->Success(flutter::EncodableValue(success));

    } else if (method == "reloadConfig") {
        const auto* args = std::get_if<flutter::EncodableMap>(arguments);
        if (args) {
            auto config_it = args->find(flutter::EncodableValue("configPath"));
            if (config_it != args->end()) {
                std::string configPath = std::get<std::string>(config_it->second);
                bool success = core.ReloadConfig(configPath);
                result->Success(flutter::EncodableValue(success));
                return;
            }
        }
        result->Success(flutter::EncodableValue(false));

    } else if (method == "isCoreRunning") {
        result->Success(flutter::EncodableValue(core.IsRunning()));

    } else if (method == "getCoreVersion") {
        result->Success(flutter::EncodableValue(core.GetVersion()));

    } else if (method == "getVpnState") {
        result->Success(flutter::EncodableValue(core.GetState()));

    } else if (method == "setSystemProxy") {
        const auto* args = std::get_if<flutter::EncodableMap>(arguments);
        if (args) {
            bool enable = false;
            std::string host = "127.0.0.1";
            int port = 7890;

            auto enable_it = args->find(flutter::EncodableValue("enable"));
            if (enable_it != args->end()) {
                enable = std::get<bool>(enable_it->second);
            }

            auto host_it = args->find(flutter::EncodableValue("host"));
            if (host_it != args->end()) {
                host = std::get<std::string>(host_it->second);
            }

            auto port_it = args->find(flutter::EncodableValue("port"));
            if (port_it != args->end()) {
                port = std::get<int>(port_it->second);
            }

            bool success = SetSystemProxy(enable, host, port);
            result->Success(flutter::EncodableValue(success));
            return;
        }
        result->Success(flutter::EncodableValue(false));

    } else if (method == "getTrafficStats") {
        auto stats = core.GetTrafficStats();
        flutter::EncodableMap data;
        data[flutter::EncodableValue("upload")] = flutter::EncodableValue(static_cast<int64_t>(stats.upload));
        data[flutter::EncodableValue("download")] = flutter::EncodableValue(static_cast<int64_t>(stats.download));
        data[flutter::EncodableValue("uploadSpeed")] = flutter::EncodableValue(static_cast<int64_t>(stats.uploadSpeed));
        data[flutter::EncodableValue("downloadSpeed")] = flutter::EncodableValue(static_cast<int64_t>(stats.downloadSpeed));
        result->Success(flutter::EncodableValue(data));

    } else if (method == "testProxyDelay") {
        const auto* args = std::get_if<flutter::EncodableMap>(arguments);
        if (args) {
            std::string proxy, url = "http://www.gstatic.com/generate_204";
            int timeout = 5000;

            auto proxy_it = args->find(flutter::EncodableValue("proxy"));
            if (proxy_it != args->end()) {
                proxy = std::get<std::string>(proxy_it->second);
            }

            auto url_it = args->find(flutter::EncodableValue("url"));
            if (url_it != args->end()) {
                url = std::get<std::string>(url_it->second);
            }

            auto timeout_it = args->find(flutter::EncodableValue("timeout"));
            if (timeout_it != args->end()) {
                timeout = std::get<int>(timeout_it->second);
            }

            int delay = core.TestDelay(proxy, url, timeout);
            result->Success(flutter::EncodableValue(delay));
            return;
        }
        result->Success(flutter::EncodableValue(-1));

    } else if (method == "switchProxy") {
        const auto* args = std::get_if<flutter::EncodableMap>(arguments);
        if (args) {
            std::string selector, proxy;

            auto selector_it = args->find(flutter::EncodableValue("selector"));
            if (selector_it != args->end()) {
                selector = std::get<std::string>(selector_it->second);
            }

            auto proxy_it = args->find(flutter::EncodableValue("proxy"));
            if (proxy_it != args->end()) {
                proxy = std::get<std::string>(proxy_it->second);
            }

            bool success = core.SwitchProxy(selector, proxy);
            result->Success(flutter::EncodableValue(success));
            return;
        }
        result->Success(flutter::EncodableValue(false));

    } else if (method == "getConnections") {
        std::string connections = core.GetConnections();
        result->Success(flutter::EncodableValue(connections));

    } else if (method == "exportLogs") {
        std::string path = core.ExportLogs();
        if (!path.empty()) {
            result->Success(flutter::EncodableValue(path));
        } else {
            result->Success(flutter::EncodableValue());
        }

    } else if (method == "copyLogsToClipboard") {
        std::string logs = core.GetLogs();
        if (OpenClipboard(nullptr)) {
            EmptyClipboard();
            HGLOBAL hg = GlobalAlloc(GMEM_MOVEABLE, logs.size() + 1);
            if (hg) {
                memcpy(GlobalLock(hg), logs.c_str(), logs.size() + 1);
                GlobalUnlock(hg);
                SetClipboardData(CF_TEXT, hg);
            }
            CloseClipboard();
            result->Success(flutter::EncodableValue(true));
        } else {
            result->Success(flutter::EncodableValue(false));
        }

    } else if (method == "getDeviceInfo") {
        auto info = GetDeviceInfo();
        result->Success(flutter::EncodableValue(info));

    } else if (method == "setAutoStart") {
        const auto* args = std::get_if<flutter::EncodableMap>(arguments);
        if (args) {
            auto enable_it = args->find(flutter::EncodableValue("enable"));
            if (enable_it != args->end()) {
                bool enable = std::get<bool>(enable_it->second);
                bool success = SetAutoStart(enable);
                result->Success(flutter::EncodableValue(success));
                return;
            }
        }
        result->Success(flutter::EncodableValue(false));

    } else if (method == "isAutoStartEnabled") {
        result->Success(flutter::EncodableValue(IsAutoStartEnabled()));

    } else if (method == "openAppSettings") {
        // Windows doesn't have app settings page
        result->Success(flutter::EncodableValue(true));

    } else if (method == "startVpn" || method == "stopVpn" ||
               method == "requestVpnPermission" ||
               method == "checkBatteryOptimization" ||
               method == "requestIgnoreBatteryOptimization" ||
               method == "installSystemExtension" ||
               method == "checkSystemExtension") {
        // These are not applicable on Windows
        result->Success(flutter::EncodableValue(true));

    } else {
        result->NotImplemented();
    }
}

bool PlatformChannel::SetSystemProxy(bool enable, const std::string& host, int port) {
    HKEY hKey;
    LONG result = RegOpenKeyExW(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
        0, KEY_SET_VALUE, &hKey);

    if (result != ERROR_SUCCESS) {
        return false;
    }

    DWORD proxyEnable = enable ? 1 : 0;
    RegSetValueExW(hKey, L"ProxyEnable", 0, REG_DWORD, (BYTE*)&proxyEnable, sizeof(DWORD));

    if (enable) {
        std::string proxyServer = host + ":" + std::to_string(port);
        std::wstring wProxyServer(proxyServer.begin(), proxyServer.end());
        RegSetValueExW(hKey, L"ProxyServer", 0, REG_SZ,
            (BYTE*)wProxyServer.c_str(), static_cast<DWORD>((wProxyServer.size() + 1) * sizeof(wchar_t)));
    }

    RegCloseKey(hKey);

    // Notify system of proxy change
    InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
    InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);

    return true;
}

bool PlatformChannel::SetAutoStart(bool enable) {
    HKEY hKey;
    LONG result = RegOpenKeyExW(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
        0, KEY_SET_VALUE, &hKey);

    if (result != ERROR_SUCCESS) {
        return false;
    }

    if (enable) {
        wchar_t path[MAX_PATH];
        GetModuleFileNameW(nullptr, path, MAX_PATH);
        RegSetValueExW(hKey, L"Vortex", 0, REG_SZ, (BYTE*)path, static_cast<DWORD>((wcslen(path) + 1) * sizeof(wchar_t)));
    } else {
        RegDeleteValueW(hKey, L"Vortex");
    }

    RegCloseKey(hKey);
    return true;
}

bool PlatformChannel::IsAutoStartEnabled() {
    HKEY hKey;
    LONG result = RegOpenKeyExW(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
        0, KEY_QUERY_VALUE, &hKey);

    if (result != ERROR_SUCCESS) {
        return false;
    }

    wchar_t value[MAX_PATH];
    DWORD size = sizeof(value);
    result = RegQueryValueExW(hKey, L"Vortex", nullptr, nullptr, (BYTE*)value, &size);
    RegCloseKey(hKey);

    return result == ERROR_SUCCESS;
}

std::map<std::string, flutter::EncodableValue> PlatformChannel::GetDeviceInfo() {
    std::map<std::string, flutter::EncodableValue> info;

    // Windows version
    OSVERSIONINFOEXW osvi = {0};
    osvi.dwOSVersionInfoSize = sizeof(osvi);

    // Get actual version using RtlGetVersion (GetVersionEx is deprecated)
    typedef NTSTATUS(WINAPI* RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);
    HMODULE hMod = GetModuleHandleW(L"ntdll.dll");
    if (hMod) {
        auto RtlGetVersion = (RtlGetVersionPtr)GetProcAddress(hMod, "RtlGetVersion");
        if (RtlGetVersion) {
            RtlGetVersion((PRTL_OSVERSIONINFOW)&osvi);
        }
    }

    std::string version = std::to_string(osvi.dwMajorVersion) + "." +
                          std::to_string(osvi.dwMinorVersion) + "." +
                          std::to_string(osvi.dwBuildNumber);
    info["version"] = flutter::EncodableValue(version);

    // Computer name
    wchar_t computerName[MAX_COMPUTERNAME_LENGTH + 1];
    DWORD size = sizeof(computerName) / sizeof(wchar_t);
    if (GetComputerNameW(computerName, &size)) {
        std::wstring wName(computerName);
        std::string name(wName.begin(), wName.end());
        info["model"] = flutter::EncodableValue(name);
    }

    info["manufacturer"] = flutter::EncodableValue("Microsoft");
    info["platform"] = flutter::EncodableValue("windows");

    // Architecture
    SYSTEM_INFO si;
    GetNativeSystemInfo(&si);
    std::string arch;
    switch (si.wProcessorArchitecture) {
        case PROCESSOR_ARCHITECTURE_AMD64:
            arch = "x64";
            break;
        case PROCESSOR_ARCHITECTURE_ARM64:
            arch = "arm64";
            break;
        case PROCESSOR_ARCHITECTURE_INTEL:
            arch = "x86";
            break;
        default:
            arch = "unknown";
    }
    info["abi"] = flutter::EncodableValue(arch);

    return info;
}

std::string PlatformChannel::GetConfigDirectory() {
    wchar_t* appData = nullptr;
    std::string configDir;

    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &appData))) {
        std::wstring wPath(appData);
        std::string path(wPath.begin(), wPath.end());
        configDir = path + "\\com.vortex.helper";
        CoTaskMemFree(appData);
    } else {
        configDir = "C:\\ProgramData\\Vortex";
    }

    // Create directory if it doesn't exist
    CreateDirectoryA(configDir.c_str(), nullptr);

    return configDir;
}

void PlatformChannel::SendEvent(const std::string& type, const flutter::EncodableValue& data) {
    if (event_sink_) {
        flutter::EncodableMap event;
        event[flutter::EncodableValue("type")] = flutter::EncodableValue(type);
        event[flutter::EncodableValue("data")] = data;
        event_sink_->Success(flutter::EncodableValue(event));
    }
}
