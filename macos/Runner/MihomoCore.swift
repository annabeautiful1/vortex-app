import Foundation
import Cocoa

/// Mihomo Core Manager for macOS
/// Handles core process lifecycle, REST API communication, and traffic statistics
class MihomoCore {
    static let shared = MihomoCore()

    struct TrafficStats {
        var upload: Int64 = 0
        var download: Int64 = 0
        var uploadSpeed: Int64 = 0
        var downloadSpeed: Int64 = 0
    }

    typealias StateCallback = (String) -> Void
    typealias TrafficCallback = (TrafficStats) -> Void
    typealias LogCallback = (String) -> Void
    typealias ErrorCallback = (String) -> Void

    private var workDir: String = ""
    private var corePath: String = ""
    private var configPath: String = ""
    private var state: String = "disconnected"

    private var controllerHost: String = "127.0.0.1"
    private var controllerPort: Int = 9090
    private var controllerSecret: String = ""

    private var process: Process?
    private var isRunning: Bool = false
    private var stopMonitoring: Bool = false

    private var trafficTimer: Timer?
    private var lastUpload: Int64 = 0
    private var lastDownload: Int64 = 0
    private var lastTime: Date?

    var stateCallback: StateCallback?
    var trafficCallback: TrafficCallback?
    var logCallback: LogCallback?
    var errorCallback: ErrorCallback?

    private init() {}

    /// Initialize core
    func initialize(workDir: String) -> Bool {
        self.workDir = workDir

        // Ensure work directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: workDir) {
            do {
                try fileManager.createDirectory(atPath: workDir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create work directory: \(error)")
                return false
            }
        }

        // Core binary path
        corePath = workDir + "/mihomo"

        // Check if core exists
        if !fileManager.fileExists(atPath: corePath) {
            // Try to extract from bundle
            if let bundlePath = Bundle.main.path(forResource: "mihomo", ofType: nil) {
                do {
                    try fileManager.copyItem(atPath: bundlePath, toPath: corePath)
                    // Make executable
                    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: corePath)
                } catch {
                    errorCallback?("Failed to extract core binary: \(error.localizedDescription)")
                    return false
                }
            } else {
                errorCallback?("Core binary not found")
                return false
            }
        }

        return true
    }

    /// Start core with config
    func start(configPath: String) -> Bool {
        if isRunning {
            return true
        }

        self.configPath = configPath
        parseControllerSettings(configPath: configPath)

        process = Process()
        process?.executableURL = URL(fileURLWithPath: corePath)
        process?.arguments = ["-d", workDir, "-f", configPath]
        process?.currentDirectoryURL = URL(fileURLWithPath: workDir)

        // Capture output
        let pipe = Pipe()
        process?.standardOutput = pipe
        process?.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                self?.logCallback?(output)
            }
        }

        do {
            try process?.run()

            // Wait a bit
            Thread.sleep(forTimeInterval: 0.5)

            if process?.isRunning == true {
                isRunning = true
                state = "connected"
                stopMonitoring = false
                stateCallback?(state)
                startTrafficMonitor()
                return true
            } else {
                errorCallback?("Core process exited immediately")
                return false
            }
        } catch {
            errorCallback?("Failed to start core: \(error.localizedDescription)")
            return false
        }
    }

    /// Stop core
    func stop() -> Bool {
        if !isRunning {
            return true
        }

        state = "disconnecting"
        stateCallback?(state)

        stopMonitoring = true
        trafficTimer?.invalidate()
        trafficTimer = nil

        process?.terminate()
        process?.waitUntilExit()
        process = nil

        isRunning = false
        state = "disconnected"
        stateCallback?(state)

        return true
    }

    /// Reload config
    func reloadConfig(configPath: String) -> Bool {
        let body = "{\"path\":\"\(configPath)\"}"
        let result = httpPut(path: "/configs?force=true", body: body)
        if result != nil {
            self.configPath = configPath
            parseControllerSettings(configPath: configPath)
            return true
        }
        return false
    }

    /// Check if running
    func checkIsRunning() -> Bool {
        return isRunning && (process?.isRunning ?? false)
    }

    /// Get state
    func getState() -> String {
        return state
    }

    /// Get version
    func getVersion() -> String {
        guard let response = httpGet(path: "/version") else {
            return "unknown"
        }

        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = json["version"] as? String {
            return version
        }
        return "unknown"
    }

    /// Get traffic stats
    func getTrafficStats() -> TrafficStats {
        var stats = TrafficStats()

        guard let response = httpGet(path: "/traffic") else {
            return stats
        }

        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            stats.upload = json["up"] as? Int64 ?? 0
            stats.download = json["down"] as? Int64 ?? 0
        }

        return stats
    }

    /// Test proxy delay
    func testDelay(proxy: String, url: String, timeout: Int) -> Int {
        let encodedProxy = proxy.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? proxy
        let path = "/proxies/\(encodedProxy)/delay?timeout=\(timeout)&url=\(url)"

        guard let response = httpGet(path: path) else {
            return -1
        }

        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let delay = json["delay"] as? Int {
            return delay
        }
        return -1
    }

    /// Switch proxy
    func switchProxy(selector: String, proxy: String) -> Bool {
        let encodedSelector = selector.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? selector
        let body = "{\"name\":\"\(proxy)\"}"
        return httpPut(path: "/proxies/\(encodedSelector)", body: body) != nil
    }

    /// Get connections
    func getConnections() -> String {
        return httpGet(path: "/connections") ?? ""
    }

    /// Get logs
    func getLogs() -> String {
        let logPath = workDir + "/logs/mihomo.log"
        do {
            return try String(contentsOfFile: logPath, encoding: .utf8)
        } catch {
            return "No logs available"
        }
    }

    /// Export logs
    func exportLogs() -> String? {
        let logs = getLogs()
        let timestamp = Int(Date().timeIntervalSince1970)
        let exportPath = workDir + "/vortex_logs_\(timestamp).txt"

        do {
            try logs.write(toFile: exportPath, atomically: true, encoding: .utf8)
            return exportPath
        } catch {
            return nil
        }
    }

    // MARK: - Private Methods

    private func parseControllerSettings(configPath: String) {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return
        }

        // Parse external-controller
        if let range = content.range(of: "external-controller:\\s*['\"]?([^'\":\\s]+):?(\\d+)?['\"]?",
                                      options: .regularExpression) {
            let match = String(content[range])
            let components = match.replacingOccurrences(of: "external-controller:", with: "")
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "\"", with: "")
                .split(separator: ":")

            if components.count >= 1 {
                controllerHost = String(components[0])
            }
            if components.count >= 2, let port = Int(components[1]) {
                controllerPort = port
            }
        }

        // Parse secret
        if let range = content.range(of: "secret:\\s*['\"]?([^'\"\\s]+)['\"]?",
                                      options: .regularExpression) {
            let match = String(content[range])
            controllerSecret = match.replacingOccurrences(of: "secret:", with: "")
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "\"", with: "")
        }
    }

    private func startTrafficMonitor() {
        trafficTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning, !self.stopMonitoring else { return }

            var stats = self.getTrafficStats()
            let now = Date()

            if let lastTime = self.lastTime {
                let timeDelta = now.timeIntervalSince(lastTime)
                if timeDelta > 0 {
                    stats.uploadSpeed = Int64(Double(stats.upload - self.lastUpload) / timeDelta)
                    stats.downloadSpeed = Int64(Double(stats.download - self.lastDownload) / timeDelta)
                    self.trafficCallback?(stats)
                }
            }

            self.lastUpload = stats.upload
            self.lastDownload = stats.download
            self.lastTime = now
        }
    }

    private func httpGet(path: String) -> String? {
        let urlString = "http://\(controllerHost):\(controllerPort)\(path)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        if !controllerSecret.isEmpty {
            request.setValue("Bearer \(controllerSecret)", forHTTPHeaderField: "Authorization")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data {
                result = String(data: data, encoding: .utf8)
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        return result
    }

    private func httpPut(path: String, body: String) -> String? {
        let urlString = "http://\(controllerHost):\(controllerPort)\(path)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        if !controllerSecret.isEmpty {
            request.setValue("Bearer \(controllerSecret)", forHTTPHeaderField: "Authorization")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                result = "success"
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        return result
    }
}
