package com.vortex.vortex_app.core

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

/**
 * Mihomo (Clash.Meta) Core Manager
 * Handles core process lifecycle, REST API communication, and traffic statistics
 */
object MihomoCore {
    private const val TAG = "MihomoCore"

    // Default external controller settings
    private var controllerHost = "127.0.0.1"
    private var controllerPort = 9090
    private var controllerSecret = ""

    // Core process
    private var coreProcess: Process? = null
    private var isRunning = false
    private var currentConfigPath: String? = null

    // HTTP client for REST API
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .build()

    // Coroutine scope for async operations
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // State listener
    private var stateListener: CoreStateListener? = null

    interface CoreStateListener {
        fun onStateChanged(state: String)
        fun onTrafficUpdate(upload: Long, download: Long, uploadSpeed: Long, downloadSpeed: Long)
        fun onLog(message: String)
        fun onError(error: String)
    }

    fun setStateListener(listener: CoreStateListener?) {
        stateListener = listener
    }

    /**
     * Initialize the core - extract binary if needed
     */
    fun init(context: Context): Boolean {
        try {
            val coreDir = File(context.filesDir, "mihomo")
            if (!coreDir.exists()) {
                coreDir.mkdirs()
            }

            // Check if core binary exists
            val coreBinary = File(coreDir, "mihomo")
            if (!coreBinary.exists()) {
                // Extract from assets
                val success = extractCoreFromAssets(context, coreBinary)
                if (!success) {
                    Log.e(TAG, "Failed to extract core binary")
                    return false
                }
            }

            // Make executable
            if (!coreBinary.canExecute()) {
                coreBinary.setExecutable(true)
            }

            Log.i(TAG, "Core initialized at ${coreBinary.absolutePath}")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize core", e)
            return false
        }
    }

    /**
     * Extract core binary from APK assets
     */
    private fun extractCoreFromAssets(context: Context, target: File): Boolean {
        return try {
            // Try to find the correct binary for this architecture
            val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
            val assetName = when {
                abi.contains("arm64") -> "mihomo-arm64"
                abi.contains("armeabi-v7a") || abi.contains("arm") -> "mihomo-arm"
                abi.contains("x86_64") -> "mihomo-amd64"
                abi.contains("x86") -> "mihomo-386"
                else -> "mihomo-arm64"
            }

            context.assets.open("bin/$assetName").use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output)
                }
            }

            target.setExecutable(true)
            Log.i(TAG, "Extracted core binary: $assetName -> ${target.absolutePath}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to extract core from assets", e)
            false
        }
    }

    /**
     * Start the Mihomo core with given config
     */
    fun start(context: Context, configPath: String): Boolean {
        if (isRunning) {
            Log.w(TAG, "Core is already running")
            return true
        }

        try {
            val coreDir = File(context.filesDir, "mihomo")
            val coreBinary = File(coreDir, "mihomo")

            if (!coreBinary.exists() || !coreBinary.canExecute()) {
                Log.e(TAG, "Core binary not found or not executable")
                stateListener?.onError("Core binary not found")
                return false
            }

            // Parse config to get controller settings
            parseControllerSettings(configPath)

            // Build process command
            val command = listOf(
                coreBinary.absolutePath,
                "-d", coreDir.absolutePath,
                "-f", configPath
            )

            Log.i(TAG, "Starting core: ${command.joinToString(" ")}")

            val processBuilder = ProcessBuilder(command)
                .directory(coreDir)
                .redirectErrorStream(true)

            // Set environment
            processBuilder.environment()["HOME"] = coreDir.absolutePath

            coreProcess = processBuilder.start()
            currentConfigPath = configPath

            // Start log reader
            startLogReader()

            // Wait a bit and check if process is running
            Thread.sleep(500)

            if (coreProcess?.isAlive == true) {
                isRunning = true
                stateListener?.onStateChanged("connected")

                // Start traffic monitoring
                startTrafficMonitor()

                Log.i(TAG, "Core started successfully")
                return true
            } else {
                val exitCode = coreProcess?.exitValue() ?: -1
                Log.e(TAG, "Core exited immediately with code: $exitCode")
                stateListener?.onError("Core failed to start (exit code: $exitCode)")
                return false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start core", e)
            stateListener?.onError("Failed to start core: ${e.message}")
            return false
        }
    }

    /**
     * Stop the Mihomo core
     */
    fun stop(): Boolean {
        try {
            isRunning = false
            stateListener?.onStateChanged("disconnecting")

            // Try graceful shutdown via API first
            try {
                scope.launch {
                    try {
                        // There's no shutdown endpoint in Mihomo, so we just kill the process
                    } catch (e: Exception) {
                        // Ignore
                    }
                }
            } catch (e: Exception) {
                // Ignore
            }

            // Kill process
            coreProcess?.destroy()
            coreProcess?.waitFor(3, TimeUnit.SECONDS)

            if (coreProcess?.isAlive == true) {
                coreProcess?.destroyForcibly()
            }

            coreProcess = null
            currentConfigPath = null
            stateListener?.onStateChanged("disconnected")

            Log.i(TAG, "Core stopped")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop core", e)
            return false
        }
    }

    /**
     * Reload config
     */
    suspend fun reloadConfig(configPath: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val url = "http://$controllerHost:$controllerPort/configs?force=true"
                val json = JSONObject().apply {
                    put("path", configPath)
                }

                val request = Request.Builder()
                    .url(url)
                    .put(json.toString().toRequestBody("application/json".toMediaType()))
                    .apply {
                        if (controllerSecret.isNotEmpty()) {
                            addHeader("Authorization", "Bearer $controllerSecret")
                        }
                    }
                    .build()

                val response = httpClient.newCall(request).execute()
                val success = response.isSuccessful
                response.close()

                if (success) {
                    currentConfigPath = configPath
                    Log.i(TAG, "Config reloaded: $configPath")
                }
                success
            } catch (e: Exception) {
                Log.e(TAG, "Failed to reload config", e)
                false
            }
        }
    }

    /**
     * Check if core is running
     */
    fun isRunning(): Boolean {
        return isRunning && coreProcess?.isAlive == true
    }

    /**
     * Get core version via API
     */
    suspend fun getVersion(): String? {
        return withContext(Dispatchers.IO) {
            try {
                val url = "http://$controllerHost:$controllerPort/version"
                val request = Request.Builder()
                    .url(url)
                    .get()
                    .apply {
                        if (controllerSecret.isNotEmpty()) {
                            addHeader("Authorization", "Bearer $controllerSecret")
                        }
                    }
                    .build()

                val response = httpClient.newCall(request).execute()
                if (response.isSuccessful) {
                    val body = response.body?.string()
                    response.close()
                    val json = JSONObject(body ?: "{}")
                    json.optString("version", null)
                } else {
                    response.close()
                    null
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get version", e)
                null
            }
        }
    }

    /**
     * Get traffic statistics
     */
    suspend fun getTraffic(): TrafficStats? {
        return withContext(Dispatchers.IO) {
            try {
                val url = "http://$controllerHost:$controllerPort/traffic"
                val request = Request.Builder()
                    .url(url)
                    .get()
                    .apply {
                        if (controllerSecret.isNotEmpty()) {
                            addHeader("Authorization", "Bearer $controllerSecret")
                        }
                    }
                    .build()

                val response = httpClient.newCall(request).execute()
                if (response.isSuccessful) {
                    val body = response.body?.string()
                    response.close()
                    val json = JSONObject(body ?: "{}")
                    TrafficStats(
                        upload = json.optLong("up", 0),
                        download = json.optLong("down", 0)
                    )
                } else {
                    response.close()
                    null
                }
            } catch (e: Exception) {
                // Traffic endpoint returns streaming data, handle differently
                null
            }
        }
    }

    /**
     * Get connections
     */
    suspend fun getConnections(): String? {
        return withContext(Dispatchers.IO) {
            try {
                val url = "http://$controllerHost:$controllerPort/connections"
                val request = Request.Builder()
                    .url(url)
                    .get()
                    .apply {
                        if (controllerSecret.isNotEmpty()) {
                            addHeader("Authorization", "Bearer $controllerSecret")
                        }
                    }
                    .build()

                val response = httpClient.newCall(request).execute()
                val body = if (response.isSuccessful) response.body?.string() else null
                response.close()
                body
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get connections", e)
                null
            }
        }
    }

    /**
     * Switch proxy
     */
    suspend fun switchProxy(selector: String, proxy: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val url = "http://$controllerHost:$controllerPort/proxies/$selector"
                val json = JSONObject().apply {
                    put("name", proxy)
                }

                val request = Request.Builder()
                    .url(url)
                    .put(json.toString().toRequestBody("application/json".toMediaType()))
                    .apply {
                        if (controllerSecret.isNotEmpty()) {
                            addHeader("Authorization", "Bearer $controllerSecret")
                        }
                    }
                    .build()

                val response = httpClient.newCall(request).execute()
                val success = response.isSuccessful
                response.close()
                success
            } catch (e: Exception) {
                Log.e(TAG, "Failed to switch proxy", e)
                false
            }
        }
    }

    /**
     * Test proxy delay
     */
    suspend fun testDelay(proxy: String, url: String = "http://www.gstatic.com/generate_204", timeout: Int = 5000): Int {
        return withContext(Dispatchers.IO) {
            try {
                val apiUrl = "http://$controllerHost:$controllerPort/proxies/$proxy/delay?timeout=$timeout&url=$url"
                val request = Request.Builder()
                    .url(apiUrl)
                    .get()
                    .apply {
                        if (controllerSecret.isNotEmpty()) {
                            addHeader("Authorization", "Bearer $controllerSecret")
                        }
                    }
                    .build()

                val response = httpClient.newCall(request).execute()
                if (response.isSuccessful) {
                    val body = response.body?.string()
                    response.close()
                    val json = JSONObject(body ?: "{}")
                    json.optInt("delay", -1)
                } else {
                    response.close()
                    -1
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to test delay for $proxy", e)
                -1
            }
        }
    }

    /**
     * Parse controller settings from config file
     */
    private fun parseControllerSettings(configPath: String) {
        try {
            val configFile = File(configPath)
            if (!configFile.exists()) return

            val content = configFile.readText()

            // Parse external-controller
            val controllerRegex = Regex("""external-controller:\s*['"]?([^'":\s]+):?(\d+)?['"]?""")
            controllerRegex.find(content)?.let { match ->
                controllerHost = match.groupValues[1].ifEmpty { "127.0.0.1" }
                controllerPort = match.groupValues[2].toIntOrNull() ?: 9090
            }

            // Parse secret
            val secretRegex = Regex("""secret:\s*['"]?([^'"\s]+)['"]?""")
            secretRegex.find(content)?.let { match ->
                controllerSecret = match.groupValues[1]
            }

            Log.i(TAG, "Controller: $controllerHost:$controllerPort, secret: ${controllerSecret.take(3)}...")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse controller settings", e)
        }
    }

    /**
     * Start log reader coroutine
     */
    private fun startLogReader() {
        scope.launch {
            try {
                coreProcess?.inputStream?.bufferedReader()?.useLines { lines ->
                    lines.forEach { line ->
                        if (line.isNotBlank()) {
                            Log.d(TAG, "[Core] $line")
                            stateListener?.onLog(line)
                        }
                    }
                }
            } catch (e: Exception) {
                if (isRunning) {
                    Log.e(TAG, "Log reader error", e)
                }
            }
        }
    }

    /**
     * Start traffic monitoring
     */
    private var lastUpload = 0L
    private var lastDownload = 0L
    private var lastTime = 0L

    private fun startTrafficMonitor() {
        scope.launch {
            while (isRunning) {
                try {
                    val traffic = getTraffic()
                    if (traffic != null) {
                        val now = System.currentTimeMillis()
                        val timeDelta = (now - lastTime) / 1000.0

                        if (lastTime > 0 && timeDelta > 0) {
                            val uploadSpeed = ((traffic.upload - lastUpload) / timeDelta).toLong()
                            val downloadSpeed = ((traffic.download - lastDownload) / timeDelta).toLong()

                            stateListener?.onTrafficUpdate(
                                traffic.upload,
                                traffic.download,
                                uploadSpeed,
                                downloadSpeed
                            )
                        }

                        lastUpload = traffic.upload
                        lastDownload = traffic.download
                        lastTime = now
                    }

                    delay(1000) // Update every second
                } catch (e: Exception) {
                    if (isRunning) {
                        Log.e(TAG, "Traffic monitor error", e)
                    }
                    delay(5000) // Retry after 5 seconds on error
                }
            }
        }
    }

    /**
     * Get logs from file
     */
    fun getLogs(context: Context): String {
        return try {
            val logFile = File(context.filesDir, "mihomo/logs/mihomo.log")
            if (logFile.exists()) {
                logFile.readText().takeLast(100000) // Last 100KB
            } else {
                "No logs available"
            }
        } catch (e: Exception) {
            "Failed to read logs: ${e.message}"
        }
    }

    /**
     * Export logs to file
     */
    fun exportLogs(context: Context): String? {
        return try {
            val logs = getLogs(context)
            val exportFile = File(context.getExternalFilesDir(null), "vortex_logs_${System.currentTimeMillis()}.txt")
            exportFile.writeText(logs)
            exportFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to export logs", e)
            null
        }
    }

    data class TrafficStats(
        val upload: Long,
        val download: Long
    )
}
