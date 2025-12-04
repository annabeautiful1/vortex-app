// MihomoCore.cpp - Mihomo Core Manager Implementation for Windows
#include "mihomo_core.h"

#include <winhttp.h>
#include <shlwapi.h>
#include <fstream>
#include <sstream>
#include <regex>
#include <chrono>
#include <iostream>

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "shlwapi.lib")

MihomoCore& MihomoCore::GetInstance() {
    static MihomoCore instance;
    return instance;
}

MihomoCore::MihomoCore()
    : controllerHost_("127.0.0.1"),
      controllerPort_(9090),
      processHandle_(nullptr),
      processThread_(nullptr),
      processId_(0),
      isRunning_(false),
      stopMonitoring_(false),
      lastUpload_(0),
      lastDownload_(0),
      lastTime_(0),
      state_("disconnected") {}

MihomoCore::~MihomoCore() {
    Stop();
}

bool MihomoCore::Init(const std::string& workDir) {
    workDir_ = workDir;

    // Ensure work directory exists
    CreateDirectoryA(workDir.c_str(), nullptr);

    // Core binary path
    corePath_ = workDir + "\\mihomo.exe";

    // Check if core exists
    if (GetFileAttributesA(corePath_.c_str()) == INVALID_FILE_ATTRIBUTES) {
        if (errorCallback_) {
            errorCallback_("Core binary not found: " + corePath_);
        }
        return false;
    }

    return true;
}

bool MihomoCore::Start(const std::string& configPath) {
    if (isRunning_) {
        return true;
    }

    configPath_ = configPath;
    ParseControllerSettings(configPath);

    // Build command line
    std::string cmdLine = "\"" + corePath_ + "\" -d \"" + workDir_ + "\" -f \"" + configPath + "\"";

    STARTUPINFOA si = {0};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;

    PROCESS_INFORMATION pi = {0};

    // Create process
    if (!CreateProcessA(
            nullptr,
            const_cast<char*>(cmdLine.c_str()),
            nullptr,
            nullptr,
            FALSE,
            CREATE_NO_WINDOW,
            nullptr,
            workDir_.c_str(),
            &si,
            &pi)) {
        if (errorCallback_) {
            errorCallback_("Failed to start core process");
        }
        return false;
    }

    processHandle_ = pi.hProcess;
    processThread_ = pi.hThread;
    processId_ = pi.dwProcessId;

    // Wait a bit for core to start
    Sleep(500);

    // Check if process is still running
    DWORD exitCode;
    if (GetExitCodeProcess(processHandle_, &exitCode) && exitCode != STILL_ACTIVE) {
        if (errorCallback_) {
            errorCallback_("Core process exited immediately");
        }
        CloseHandle(processHandle_);
        CloseHandle(processThread_);
        processHandle_ = nullptr;
        processThread_ = nullptr;
        return false;
    }

    isRunning_ = true;
    state_ = "connected";
    stopMonitoring_ = false;

    if (stateCallback_) {
        stateCallback_(state_);
    }

    // Start monitoring
    StartTrafficMonitor();

    return true;
}

bool MihomoCore::Stop() {
    if (!isRunning_) {
        return true;
    }

    state_ = "disconnecting";
    if (stateCallback_) {
        stateCallback_(state_);
    }

    StopMonitoring();

    // Terminate process
    if (processHandle_) {
        TerminateProcess(processHandle_, 0);
        WaitForSingleObject(processHandle_, 3000);
        CloseHandle(processHandle_);
        processHandle_ = nullptr;
    }

    if (processThread_) {
        CloseHandle(processThread_);
        processThread_ = nullptr;
    }

    processId_ = 0;
    isRunning_ = false;
    state_ = "disconnected";

    if (stateCallback_) {
        stateCallback_(state_);
    }

    return true;
}

bool MihomoCore::ReloadConfig(const std::string& configPath) {
    std::string body = "{\"path\":\"" + configPath + "\"}";
    std::string response = HttpPut("/configs?force=true", body);
    if (!response.empty()) {
        configPath_ = configPath;
        ParseControllerSettings(configPath);
        return true;
    }
    return false;
}

bool MihomoCore::IsRunning() const {
    if (!isRunning_ || !processHandle_) {
        return false;
    }

    DWORD exitCode;
    if (GetExitCodeProcess(processHandle_, &exitCode)) {
        return exitCode == STILL_ACTIVE;
    }
    return false;
}

std::string MihomoCore::GetVersion() {
    std::string response = HttpGet("/version");
    if (!response.empty()) {
        // Simple JSON parsing for version
        std::regex versionRegex("\"version\"\\s*:\\s*\"([^\"]+)\"");
        std::smatch match;
        if (std::regex_search(response, match, versionRegex)) {
            return match[1].str();
        }
    }
    return "unknown";
}

MihomoCore::TrafficStats MihomoCore::GetTrafficStats() {
    TrafficStats stats = {0, 0, 0, 0};

    std::string response = HttpGet("/traffic");
    if (!response.empty()) {
        // Parse JSON
        std::regex upRegex("\"up\"\\s*:\\s*(\\d+)");
        std::regex downRegex("\"down\"\\s*:\\s*(\\d+)");
        std::smatch match;

        if (std::regex_search(response, match, upRegex)) {
            stats.upload = std::stoll(match[1].str());
        }
        if (std::regex_search(response, match, downRegex)) {
            stats.download = std::stoll(match[1].str());
        }
    }

    return stats;
}

int MihomoCore::TestDelay(const std::string& proxy, const std::string& url, int timeout) {
    std::string path = "/proxies/" + proxy + "/delay?timeout=" + std::to_string(timeout) + "&url=" + url;
    std::string response = HttpGet(path);

    if (!response.empty()) {
        std::regex delayRegex("\"delay\"\\s*:\\s*(\\d+)");
        std::smatch match;
        if (std::regex_search(response, match, delayRegex)) {
            return std::stoi(match[1].str());
        }
    }
    return -1;
}

bool MihomoCore::SwitchProxy(const std::string& selector, const std::string& proxy) {
    std::string body = "{\"name\":\"" + proxy + "\"}";
    std::string response = HttpPut("/proxies/" + selector, body);
    return !response.empty();
}

std::string MihomoCore::GetConnections() {
    return HttpGet("/connections");
}

std::string MihomoCore::GetLogs() {
    std::string logPath = workDir_ + "\\logs\\mihomo.log";
    std::ifstream file(logPath);
    if (file.is_open()) {
        std::stringstream buffer;
        buffer << file.rdbuf();
        return buffer.str();
    }
    return "No logs available";
}

std::string MihomoCore::ExportLogs() {
    std::string logs = GetLogs();
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);

    std::string exportPath = workDir_ + "\\vortex_logs_" + std::to_string(time) + ".txt";
    std::ofstream file(exportPath);
    if (file.is_open()) {
        file << logs;
        file.close();
        return exportPath;
    }
    return "";
}

void MihomoCore::SetStateCallback(StateCallback callback) {
    stateCallback_ = callback;
}

void MihomoCore::SetTrafficCallback(TrafficCallback callback) {
    trafficCallback_ = callback;
}

void MihomoCore::SetLogCallback(LogCallback callback) {
    logCallback_ = callback;
}

void MihomoCore::SetErrorCallback(ErrorCallback callback) {
    errorCallback_ = callback;
}

void MihomoCore::ParseControllerSettings(const std::string& configPath) {
    std::ifstream file(configPath);
    if (!file.is_open()) return;

    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string content = buffer.str();

    // Parse external-controller
    std::regex controllerRegex("external-controller:\\s*['\"]?([^'\":\\s]+):?(\\d+)?['\"]?");
    std::smatch match;
    if (std::regex_search(content, match, controllerRegex)) {
        controllerHost_ = match[1].str();
        if (!match[2].str().empty()) {
            controllerPort_ = std::stoi(match[2].str());
        }
    }

    // Parse secret
    std::regex secretRegex("secret:\\s*['\"]?([^'\"\\s]+)['\"]?");
    if (std::regex_search(content, match, secretRegex)) {
        controllerSecret_ = match[1].str();
    }
}

void MihomoCore::StartTrafficMonitor() {
    trafficThread_ = std::thread([this]() {
        while (!stopMonitoring_) {
            if (isRunning_ && trafficCallback_) {
                TrafficStats stats = GetTrafficStats();

                ULONGLONG now = GetTickCount64();
                double timeDelta = (now - lastTime_) / 1000.0;

                if (lastTime_ > 0 && timeDelta > 0) {
                    stats.uploadSpeed = static_cast<int64_t>((stats.upload - lastUpload_) / timeDelta);
                    stats.downloadSpeed = static_cast<int64_t>((stats.download - lastDownload_) / timeDelta);

                    trafficCallback_(stats);
                }

                lastUpload_ = stats.upload;
                lastDownload_ = stats.download;
                lastTime_ = now;
            }

            Sleep(1000);
        }
    });
}

void MihomoCore::StopMonitoring() {
    stopMonitoring_ = true;

    if (trafficThread_.joinable()) {
        trafficThread_.join();
    }
    if (logThread_.joinable()) {
        logThread_.join();
    }
}

std::string MihomoCore::HttpGet(const std::string& path) {
    HINTERNET hSession = nullptr;
    HINTERNET hConnect = nullptr;
    HINTERNET hRequest = nullptr;
    std::string result;

    try {
        hSession = WinHttpOpen(L"Vortex/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME,
            WINHTTP_NO_PROXY_BYPASS, 0);

        if (!hSession) throw std::runtime_error("WinHttpOpen failed");

        std::wstring wHost(controllerHost_.begin(), controllerHost_.end());
        hConnect = WinHttpConnect(hSession, wHost.c_str(), static_cast<INTERNET_PORT>(controllerPort_), 0);
        if (!hConnect) throw std::runtime_error("WinHttpConnect failed");

        std::wstring wPath(path.begin(), path.end());
        hRequest = WinHttpOpenRequest(hConnect, L"GET", wPath.c_str(),
            nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
        if (!hRequest) throw std::runtime_error("WinHttpOpenRequest failed");

        // Add authorization header if secret is set
        if (!controllerSecret_.empty()) {
            std::wstring authHeader = L"Authorization: Bearer " +
                std::wstring(controllerSecret_.begin(), controllerSecret_.end());
            WinHttpAddRequestHeaders(hRequest, authHeader.c_str(), static_cast<DWORD>(-1),
                WINHTTP_ADDREQ_FLAG_ADD);
        }

        if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
            WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
            throw std::runtime_error("WinHttpSendRequest failed");
        }

        if (!WinHttpReceiveResponse(hRequest, nullptr)) {
            throw std::runtime_error("WinHttpReceiveResponse failed");
        }

        DWORD size = 0;
        DWORD downloaded = 0;
        do {
            if (!WinHttpQueryDataAvailable(hRequest, &size)) break;
            if (size == 0) break;

            std::vector<char> buffer(size + 1, 0);
            if (WinHttpReadData(hRequest, buffer.data(), size, &downloaded)) {
                result.append(buffer.data(), downloaded);
            }
        } while (size > 0);

    } catch (...) {
        // Ignore errors
    }

    if (hRequest) WinHttpCloseHandle(hRequest);
    if (hConnect) WinHttpCloseHandle(hConnect);
    if (hSession) WinHttpCloseHandle(hSession);

    return result;
}

std::string MihomoCore::HttpPut(const std::string& path, const std::string& body) {
    HINTERNET hSession = nullptr;
    HINTERNET hConnect = nullptr;
    HINTERNET hRequest = nullptr;
    std::string result;

    try {
        hSession = WinHttpOpen(L"Vortex/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME,
            WINHTTP_NO_PROXY_BYPASS, 0);

        if (!hSession) throw std::runtime_error("WinHttpOpen failed");

        std::wstring wHost(controllerHost_.begin(), controllerHost_.end());
        hConnect = WinHttpConnect(hSession, wHost.c_str(), static_cast<INTERNET_PORT>(controllerPort_), 0);
        if (!hConnect) throw std::runtime_error("WinHttpConnect failed");

        std::wstring wPath(path.begin(), path.end());
        hRequest = WinHttpOpenRequest(hConnect, L"PUT", wPath.c_str(),
            nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
        if (!hRequest) throw std::runtime_error("WinHttpOpenRequest failed");

        // Add headers
        std::wstring headers = L"Content-Type: application/json\r\n";
        if (!controllerSecret_.empty()) {
            headers += L"Authorization: Bearer " +
                std::wstring(controllerSecret_.begin(), controllerSecret_.end()) + L"\r\n";
        }
        WinHttpAddRequestHeaders(hRequest, headers.c_str(), static_cast<DWORD>(-1), WINHTTP_ADDREQ_FLAG_ADD);

        if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
            (LPVOID)body.c_str(), static_cast<DWORD>(body.length()), static_cast<DWORD>(body.length()), 0)) {
            throw std::runtime_error("WinHttpSendRequest failed");
        }

        if (!WinHttpReceiveResponse(hRequest, nullptr)) {
            throw std::runtime_error("WinHttpReceiveResponse failed");
        }

        // Check status code
        DWORD statusCode = 0;
        DWORD size = sizeof(statusCode);
        WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            WINHTTP_HEADER_NAME_BY_INDEX, &statusCode, &size, WINHTTP_NO_HEADER_INDEX);

        if (statusCode >= 200 && statusCode < 300) {
            result = "success";
        }

    } catch (...) {
        // Ignore errors
    }

    if (hRequest) WinHttpCloseHandle(hRequest);
    if (hConnect) WinHttpCloseHandle(hConnect);
    if (hSession) WinHttpCloseHandle(hSession);

    return result;
}
