import Foundation
import Flutter
import UIKit
import NetworkExtension

/// Platform Channel Handler for iOS
class PlatformChannel: NSObject {
    static let shared = PlatformChannel()

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private var vpnManager: NETunnelProviderManager?
    private var vpnStatus: NEVPNStatus = .disconnected

    private override init() {
        super.init()
    }

    func register(with registrar: FlutterPluginRegistrar) {
        // Method Channel
        methodChannel = FlutterMethodChannel(
            name: "com.vortex.app/core",
            binaryMessenger: registrar.messenger()
        )
        methodChannel?.setMethodCallHandler(handleMethodCall)

        // Event Channel
        eventChannel = FlutterEventChannel(
            name: "com.vortex.app/events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel?.setStreamHandler(self)

        // Load VPN configuration
        loadVPNConfiguration()

        // Observe VPN status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnStatusDidChange),
            name: .NEVPNStatusDidChange,
            object: nil
        )
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {
        case "startCore":
            // On iOS, core is managed by Network Extension
            result(true)

        case "stopCore":
            result(true)

        case "reloadConfig":
            // Reload VPN configuration
            loadVPNConfiguration()
            result(true)

        case "isCoreRunning":
            result(vpnStatus == .connected)

        case "getCoreVersion":
            result(getBundleVersion())

        case "getVpnState":
            result(vpnStatusToString(vpnStatus))

        case "startVpn":
            startVPN(result: result)

        case "stopVpn":
            stopVPN(result: result)

        case "requestVpnPermission":
            requestVPNPermission(result: result)

        case "setSystemProxy":
            // iOS doesn't support system proxy
            result(true)

        case "getTrafficStats":
            // Traffic stats need to be obtained from Network Extension
            result([
                "upload": 0,
                "download": 0,
                "uploadSpeed": 0,
                "downloadSpeed": 0
            ])

        case "copyLogsToClipboard":
            copyLogsToClipboard(result: result)

        case "exportLogs":
            exportLogs(result: result)

        case "getDeviceInfo":
            result(getDeviceInfo())

        case "openAppSettings":
            openAppSettings()
            result(true)

        case "checkBatteryOptimization", "requestIgnoreBatteryOptimization":
            // Not applicable on iOS
            result(true)

        case "setAutoStart", "isAutoStartEnabled":
            // Not applicable on iOS
            result(false)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - VPN Management

    private func loadVPNConfiguration() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                print("Failed to load VPN configuration: \(error)")
                return
            }

            if let manager = managers?.first {
                self?.vpnManager = manager
            } else {
                // Create new VPN configuration
                self?.createVPNConfiguration()
            }
        }
    }

    private func createVPNConfiguration() {
        let manager = NETunnelProviderManager()

        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = "com.vortex.vortex-app.TunnelExtension"
        tunnelProtocol.serverAddress = "Vortex VPN"
        tunnelProtocol.providerConfiguration = [:]

        manager.protocolConfiguration = tunnelProtocol
        manager.localizedDescription = "Vortex VPN"
        manager.isEnabled = true

        manager.saveToPreferences { [weak self] error in
            if let error = error {
                print("Failed to save VPN configuration: \(error)")
                return
            }

            manager.loadFromPreferences { error in
                if let error = error {
                    print("Failed to load VPN configuration: \(error)")
                    return
                }
                self?.vpnManager = manager
            }
        }
    }

    private func startVPN(result: @escaping FlutterResult) {
        guard let manager = vpnManager else {
            loadVPNConfiguration()
            result(false)
            return
        }

        do {
            try manager.connection.startVPNTunnel(options: nil)
            result(true)
        } catch {
            print("Failed to start VPN: \(error)")
            result(false)
        }
    }

    private func stopVPN(result: @escaping FlutterResult) {
        vpnManager?.connection.stopVPNTunnel()
        result(true)
    }

    private func requestVPNPermission(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                print("Failed to request VPN permission: \(error)")
                result(false)
                return
            }

            if managers?.first != nil {
                result(true)
            } else {
                self?.createVPNConfiguration()
                result(true)
            }
        }
    }

    @objc private func vpnStatusDidChange(_ notification: Notification) {
        guard let connection = notification.object as? NEVPNConnection else { return }

        vpnStatus = connection.status
        let statusString = vpnStatusToString(vpnStatus)

        sendEvent(type: "vpn_state_changed", data: statusString)
    }

    private func vpnStatusToString(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid:
            return "error"
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reasserting:
            return "connecting"
        case .disconnecting:
            return "disconnecting"
        @unknown default:
            return "disconnected"
        }
    }

    // MARK: - Logs

    private func copyLogsToClipboard(result: @escaping FlutterResult) {
        let logs = getLogs()
        UIPasteboard.general.string = logs
        result(true)
    }

    private func exportLogs(result: @escaping FlutterResult) {
        let logs = getLogs()
        let fileName = "vortex_logs_\(Int(Date().timeIntervalSince1970)).txt"

        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let filePath = documentsPath.appendingPathComponent(fileName)
            do {
                try logs.write(to: filePath, atomically: true, encoding: .utf8)
                result(filePath.path)
            } catch {
                result(nil)
            }
        } else {
            result(nil)
        }
    }

    private func getLogs() -> String {
        // Get logs from app group shared container
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.vortex.app"
        ) {
            let logPath = containerURL.appendingPathComponent("logs/vortex.log")
            if let logs = try? String(contentsOf: logPath, encoding: .utf8) {
                return logs
            }
        }
        return "No logs available"
    }

    // MARK: - Device Info

    private func getDeviceInfo() -> [String: Any] {
        var info: [String: Any] = [:]

        let device = UIDevice.current
        info["model"] = device.model
        info["manufacturer"] = "Apple"
        info["version"] = device.systemVersion
        info["platform"] = "ios"

        #if targetEnvironment(simulator)
        info["abi"] = "simulator"
        #elseif arch(arm64)
        info["abi"] = "arm64"
        #else
        info["abi"] = "unknown"
        #endif

        return info
    }

    private func getBundleVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "unknown"
    }

    // MARK: - App Settings

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Events

    private func sendEvent(type: String, data: Any) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?([
                "type": type,
                "data": data
            ])
        }
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
