import Cocoa
import FlutterMacOS
import ServiceManagement

/// Platform Channel Handler for macOS
class PlatformChannel: NSObject {
    static let shared = PlatformChannel()

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private override init() {
        super.init()
    }

    func register(with registrar: FlutterPluginRegistrar) {
        // Method Channel
        methodChannel = FlutterMethodChannel(
            name: "com.vortex.app/core",
            binaryMessenger: registrar.messenger
        )
        methodChannel?.setMethodCallHandler(handleMethodCall)

        // Event Channel
        eventChannel = FlutterEventChannel(
            name: "com.vortex.app/events",
            binaryMessenger: registrar.messenger
        )
        eventChannel?.setStreamHandler(self)

        // Initialize MihomoCore
        let configDir = getConfigDirectory()
        MihomoCore.shared.initialize(workDir: configDir)

        // Setup callbacks
        setupCallbacks()
    }

    private func setupCallbacks() {
        MihomoCore.shared.stateCallback = { [weak self] state in
            self?.sendEvent(type: "vpn_state_changed", data: state)
        }

        MihomoCore.shared.trafficCallback = { [weak self] stats in
            let data: [String: Any] = [
                "upload": stats.upload,
                "download": stats.download,
                "uploadSpeed": stats.uploadSpeed,
                "downloadSpeed": stats.downloadSpeed
            ]
            self?.sendEvent(type: "traffic_update", data: data)
        }

        MihomoCore.shared.logCallback = { [weak self] message in
            self?.sendEvent(type: "log", data: message)
        }

        MihomoCore.shared.errorCallback = { [weak self] error in
            self?.sendEvent(type: "error", data: error)
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {
        case "startCore":
            let configPath = args?["configPath"] as? String ?? ""
            let success = MihomoCore.shared.start(configPath: configPath)
            result(success)

        case "stopCore":
            let success = MihomoCore.shared.stop()
            result(success)

        case "reloadConfig":
            let configPath = args?["configPath"] as? String ?? ""
            let success = MihomoCore.shared.reloadConfig(configPath: configPath)
            result(success)

        case "isCoreRunning":
            result(MihomoCore.shared.checkIsRunning())

        case "getCoreVersion":
            result(MihomoCore.shared.getVersion())

        case "getVpnState":
            result(MihomoCore.shared.getState())

        case "setSystemProxy":
            let enable = args?["enable"] as? Bool ?? false
            let host = args?["host"] as? String ?? "127.0.0.1"
            let port = args?["port"] as? Int ?? 7890
            let success = setSystemProxy(enable: enable, host: host, port: port)
            result(success)

        case "getTrafficStats":
            let stats = MihomoCore.shared.getTrafficStats()
            result([
                "upload": stats.upload,
                "download": stats.download,
                "uploadSpeed": stats.uploadSpeed,
                "downloadSpeed": stats.downloadSpeed
            ])

        case "testProxyDelay":
            let proxy = args?["proxy"] as? String ?? ""
            let url = args?["url"] as? String ?? "http://www.gstatic.com/generate_204"
            let timeout = args?["timeout"] as? Int ?? 5000
            let delay = MihomoCore.shared.testDelay(proxy: proxy, url: url, timeout: timeout)
            result(delay)

        case "switchProxy":
            let selector = args?["selector"] as? String ?? ""
            let proxy = args?["proxy"] as? String ?? ""
            let success = MihomoCore.shared.switchProxy(selector: selector, proxy: proxy)
            result(success)

        case "getConnections":
            result(MihomoCore.shared.getConnections())

        case "exportLogs":
            result(MihomoCore.shared.exportLogs())

        case "copyLogsToClipboard":
            let logs = MihomoCore.shared.getLogs()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(logs, forType: .string)
            result(true)

        case "getDeviceInfo":
            result(getDeviceInfo())

        case "setAutoStart":
            let enable = args?["enable"] as? Bool ?? false
            let success = setAutoStart(enable: enable)
            result(success)

        case "isAutoStartEnabled":
            result(isAutoStartEnabled())

        case "openAppSettings":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?General") {
                NSWorkspace.shared.open(url)
            }
            result(true)

        case "installSystemExtension":
            // System extension installation would require a separate helper app
            result(true)

        case "checkSystemExtension":
            result(true)

        case "startVpn", "stopVpn", "requestVpnPermission",
             "checkBatteryOptimization", "requestIgnoreBatteryOptimization":
            // Not applicable on macOS (use system proxy or tun mode)
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func sendEvent(type: String, data: Any) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?([
                "type": type,
                "data": data
            ])
        }
    }

    // MARK: - System Proxy

    private func setSystemProxy(enable: Bool, host: String, port: Int) -> Bool {
        // Use networksetup command to set system proxy
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")

        // Get network services
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        listProcess.arguments = ["-listallnetworkservices"]

        let pipe = Pipe()
        listProcess.standardOutput = pipe

        do {
            try listProcess.run()
            listProcess.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return false }

            let services = output.split(separator: "\n")
                .map { String($0) }
                .filter { !$0.contains("*") && !$0.isEmpty }

            for service in services {
                if enable {
                    // Enable HTTP proxy
                    let httpProcess = Process()
                    httpProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                    httpProcess.arguments = ["-setwebproxy", service, host, String(port)]
                    try httpProcess.run()
                    httpProcess.waitUntilExit()

                    // Enable HTTPS proxy
                    let httpsProcess = Process()
                    httpsProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                    httpsProcess.arguments = ["-setsecurewebproxy", service, host, String(port)]
                    try httpsProcess.run()
                    httpsProcess.waitUntilExit()

                    // Enable SOCKS proxy
                    let socksProcess = Process()
                    socksProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                    socksProcess.arguments = ["-setsocksfirewallproxy", service, host, String(port)]
                    try socksProcess.run()
                    socksProcess.waitUntilExit()
                } else {
                    // Disable proxies
                    let httpOff = Process()
                    httpOff.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                    httpOff.arguments = ["-setwebproxystate", service, "off"]
                    try httpOff.run()
                    httpOff.waitUntilExit()

                    let httpsOff = Process()
                    httpsOff.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                    httpsOff.arguments = ["-setsecurewebproxystate", service, "off"]
                    try httpsOff.run()
                    httpsOff.waitUntilExit()

                    let socksOff = Process()
                    socksOff.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                    socksOff.arguments = ["-setsocksfirewallproxystate", service, "off"]
                    try socksOff.run()
                    socksOff.waitUntilExit()
                }
            }

            return true
        } catch {
            print("Failed to set system proxy: \(error)")
            return false
        }
    }

    // MARK: - Auto Start

    private func setAutoStart(enable: Bool) -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }

        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enable {
                    try service.register()
                } else {
                    try service.unregister()
                }
                return true
            } catch {
                print("Failed to set auto start: \(error)")
                return false
            }
        } else {
            // Legacy method for older macOS versions
            return SMLoginItemSetEnabled(bundleId as CFString, enable)
        }
    }

    private func isAutoStartEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            return service.status == .enabled
        } else {
            // For older macOS, we can't easily check this
            return false
        }
    }

    // MARK: - Device Info

    private func getDeviceInfo() -> [String: Any] {
        var info: [String: Any] = [:]

        // macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        info["version"] = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // Model
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        info["model"] = String(cString: model)

        info["manufacturer"] = "Apple"
        info["platform"] = "macos"

        // Architecture
        #if arch(arm64)
        info["abi"] = "arm64"
        #elseif arch(x86_64)
        info["abi"] = "x86_64"
        #else
        info["abi"] = "unknown"
        #endif

        return info
    }

    // MARK: - Config Directory

    private func getConfigDirectory() -> String {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let configDir = appSupport.appendingPathComponent("com.vortex.helper").path

        if !fileManager.fileExists(atPath: configDir) {
            try? fileManager.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }

        return configDir
    }
}

// MARK: - FlutterStreamHandler

extension PlatformChannel: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
