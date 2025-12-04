// MihomoCore.h - Mihomo Core Manager for Windows
#ifndef MIHOMO_CORE_H_
#define MIHOMO_CORE_H_

#include <windows.h>
#include <string>
#include <functional>
#include <memory>
#include <thread>
#include <atomic>

class MihomoCore {
public:
    struct TrafficStats {
        int64_t upload;
        int64_t download;
        int64_t uploadSpeed;
        int64_t downloadSpeed;
    };

    using StateCallback = std::function<void(const std::string&)>;
    using TrafficCallback = std::function<void(const TrafficStats&)>;
    using LogCallback = std::function<void(const std::string&)>;
    using ErrorCallback = std::function<void(const std::string&)>;

    static MihomoCore& GetInstance();

    // Initialize core
    bool Init(const std::string& workDir);

    // Start core with config
    bool Start(const std::string& configPath);

    // Stop core
    bool Stop();

    // Reload config
    bool ReloadConfig(const std::string& configPath);

    // Check if running
    bool IsRunning() const;

    // Get version
    std::string GetVersion();

    // Get traffic stats
    TrafficStats GetTrafficStats();

    // Test proxy delay
    int TestDelay(const std::string& proxy, const std::string& url, int timeout);

    // Switch proxy
    bool SwitchProxy(const std::string& selector, const std::string& proxy);

    // Get connections
    std::string GetConnections();

    // Get logs
    std::string GetLogs();

    // Export logs
    std::string ExportLogs();

    // Set callbacks
    void SetStateCallback(StateCallback callback);
    void SetTrafficCallback(TrafficCallback callback);
    void SetLogCallback(LogCallback callback);
    void SetErrorCallback(ErrorCallback callback);

    // Get current state
    std::string GetState() const { return state_; }

private:
    MihomoCore();
    ~MihomoCore();
    MihomoCore(const MihomoCore&) = delete;
    MihomoCore& operator=(const MihomoCore&) = delete;

    void ParseControllerSettings(const std::string& configPath);
    void StartLogReader();
    void StartTrafficMonitor();
    void StopMonitoring();
    std::string HttpGet(const std::string& path);
    std::string HttpPut(const std::string& path, const std::string& body);

    std::string workDir_;
    std::string corePath_;
    std::string configPath_;
    std::string state_;

    std::string controllerHost_;
    int controllerPort_;
    std::string controllerSecret_;

    HANDLE processHandle_;
    HANDLE processThread_;
    DWORD processId_;

    std::atomic<bool> isRunning_;
    std::atomic<bool> stopMonitoring_;

    std::thread logThread_;
    std::thread trafficThread_;

    int64_t lastUpload_;
    int64_t lastDownload_;
    ULONGLONG lastTime_;

    StateCallback stateCallback_;
    TrafficCallback trafficCallback_;
    LogCallback logCallback_;
    ErrorCallback errorCallback_;
};

#endif  // MIHOMO_CORE_H_
