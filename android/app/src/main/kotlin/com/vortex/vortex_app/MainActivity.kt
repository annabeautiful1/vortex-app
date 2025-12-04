package com.vortex.vortex_app

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.vortex.vortex_app.core.MihomoCore
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.vortex.app/core"
        private const val EVENT_CHANNEL = "com.vortex.app/events"
        private const val VPN_REQUEST_CODE = 1001
        private const val BATTERY_OPT_REQUEST_CODE = 1002
        private const val PREFS_NAME = "vortex_prefs"
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingVpnResult: MethodChannel.Result? = null
    private var pendingBatteryResult: MethodChannel.Result? = null
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var prefs: SharedPreferences

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // Initialize Mihomo core
        MihomoCore.init(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Core management
                "startCore" -> {
                    val configPath = call.argument<String>("configPath")
                    val workDir = call.argument<String>("workDir")
                    scope.launch {
                        val success = startCore(configPath, workDir)
                        result.success(success)
                    }
                }
                "stopCore" -> {
                    result.success(stopCore())
                }
                "reloadConfig" -> {
                    val configPath = call.argument<String>("configPath")
                    scope.launch {
                        val success = reloadConfig(configPath)
                        result.success(success)
                    }
                }
                "isCoreRunning" -> {
                    result.success(MihomoCore.isRunning())
                }
                "getCoreVersion" -> {
                    scope.launch {
                        val version = MihomoCore.getVersion()
                        result.success(version)
                    }
                }

                // VPN management
                "startVpn" -> {
                    startVpn(result)
                }
                "stopVpn" -> {
                    result.success(stopVpn())
                }
                "getVpnState" -> {
                    result.success(VortexVpnService.getState())
                }
                "requestVpnPermission" -> {
                    requestVpnPermission(result)
                }

                // System proxy (not supported on Android without root)
                "setSystemProxy" -> {
                    // Android doesn't support system-wide proxy without root
                    // VPN mode handles this
                    result.success(true)
                }

                // Traffic statistics
                "getTrafficStats" -> {
                    result.success(mapOf(
                        "upload" to VortexVpnService.totalUpload,
                        "download" to VortexVpnService.totalDownload,
                        "uploadSpeed" to VortexVpnService.uploadSpeed,
                        "downloadSpeed" to VortexVpnService.downloadSpeed
                    ))
                }

                // Logs
                "copyLogsToClipboard" -> {
                    result.success(copyLogsToClipboard())
                }
                "exportLogs" -> {
                    val path = MihomoCore.exportLogs(this)
                    result.success(path)
                }

                // Battery optimization
                "checkBatteryOptimization" -> {
                    result.success(checkBatteryOptimization())
                }
                "requestIgnoreBatteryOptimization" -> {
                    requestIgnoreBatteryOptimization(result)
                }

                // Device info
                "getDeviceInfo" -> {
                    result.success(getDeviceInfo())
                }

                // Settings
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }
                "setAutoStart" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    prefs.edit().putBoolean("auto_start", enable).apply()
                    result.success(true)
                }
                "isAutoStartEnabled" -> {
                    result.success(prefs.getBoolean("auto_start", false))
                }

                // Proxy testing
                "testProxyDelay" -> {
                    val proxy = call.argument<String>("proxy") ?: ""
                    val url = call.argument<String>("url") ?: "http://www.gstatic.com/generate_204"
                    val timeout = call.argument<Int>("timeout") ?: 5000
                    scope.launch {
                        val delay = MihomoCore.testDelay(proxy, url, timeout)
                        result.success(delay)
                    }
                }

                // Switch proxy
                "switchProxy" -> {
                    val selector = call.argument<String>("selector") ?: ""
                    val proxy = call.argument<String>("proxy") ?: ""
                    scope.launch {
                        val success = MihomoCore.switchProxy(selector, proxy)
                        result.success(success)
                    }
                }

                // Get connections
                "getConnections" -> {
                    scope.launch {
                        val connections = MihomoCore.getConnections()
                        result.success(connections)
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    setupVpnServiceListener()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    VortexVpnService.getInstance()?.stateChangeListener = null
                }
            }
        )
    }

    private fun setupVpnServiceListener() {
        VortexVpnService.getInstance()?.stateChangeListener = { type, data ->
            runOnUiThread {
                sendEvent(type, data)
            }
        }
    }

    private suspend fun startCore(configPath: String?, workDir: String?): Boolean {
        return withContext(Dispatchers.IO) {
            if (configPath == null) {
                Log.e(TAG, "Config path is null")
                return@withContext false
            }
            MihomoCore.start(this@MainActivity, configPath)
        }
    }

    private fun stopCore(): Boolean {
        return MihomoCore.stop()
    }

    private suspend fun reloadConfig(configPath: String?): Boolean {
        return withContext(Dispatchers.IO) {
            if (configPath == null) return@withContext false
            MihomoCore.reloadConfig(configPath)
        }
    }

    private fun startVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingVpnResult = result
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            // VPN permission already granted
            doStartVpn()
            result.success(true)
        }
    }

    private fun doStartVpn() {
        val configPath = getConfigPath()

        val intent = Intent(this, VortexVpnService::class.java).apply {
            action = VortexVpnService.ACTION_START
            putExtra(VortexVpnService.EXTRA_CONFIG_PATH, configPath)
            putExtra(VortexVpnService.EXTRA_WORK_DIR, filesDir.absolutePath)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }

        // Setup listener for events
        setupVpnServiceListener()
    }

    private fun getConfigPath(): String {
        // Get the current config path from shared preferences or default
        val defaultPath = "${filesDir.absolutePath}/mihomo/config.yaml"
        return prefs.getString("current_config_path", defaultPath) ?: defaultPath
    }

    private fun stopVpn(): Boolean {
        val intent = Intent(this, VortexVpnService::class.java).apply {
            action = VortexVpnService.ACTION_STOP
        }
        startService(intent)
        return true
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingVpnResult = result
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            result.success(true)
        }
    }

    private fun checkBatteryOptimization(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isIgnoringBatteryOptimizations(packageName)
        }
        return true
    }

    private fun requestIgnoreBatteryOptimization(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                pendingBatteryResult = result
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivityForResult(intent, BATTERY_OPT_REQUEST_CODE)
                return
            }
        }
        result.success(true)
    }

    private fun copyLogsToClipboard(): Boolean {
        return try {
            val logs = MihomoCore.getLogs(this)
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("Vortex Logs", logs)
            clipboard.setPrimaryClip(clip)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy logs", e)
            false
        }
    }

    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "version" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"),
            "device" to Build.DEVICE,
            "product" to Build.PRODUCT,
            "brand" to Build.BRAND
        )
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            VPN_REQUEST_CODE -> {
                if (resultCode == Activity.RESULT_OK) {
                    doStartVpn()
                    pendingVpnResult?.success(true)
                } else {
                    pendingVpnResult?.success(false)
                }
                pendingVpnResult = null
            }
            BATTERY_OPT_REQUEST_CODE -> {
                pendingBatteryResult?.success(checkBatteryOptimization())
                pendingBatteryResult = null
            }
        }
    }

    // Send events to Flutter
    private fun sendEvent(type: String, data: Any?) {
        eventSink?.success(mapOf(
            "type" to type,
            "data" to data
        ))
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
