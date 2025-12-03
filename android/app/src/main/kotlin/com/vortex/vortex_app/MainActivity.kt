package com.vortex.vortex_app

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.vortex.app/core"
    private val EVENT_CHANNEL = "com.vortex.app/events"

    private var eventSink: EventChannel.EventSink? = null
    private val VPN_REQUEST_CODE = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCore" -> {
                    val configPath = call.argument<String>("configPath")
                    result.success(startCore(configPath))
                }
                "stopCore" -> {
                    result.success(stopCore())
                }
                "startVpn" -> {
                    startVpn(result)
                }
                "stopVpn" -> {
                    result.success(stopVpn())
                }
                "setSystemProxy" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    val port = call.argument<Int>("port") ?: 7890
                    result.success(setSystemProxy(enable, port))
                }
                "getVpnState" -> {
                    result.success(getVpnState())
                }
                "getCoreVersion" -> {
                    result.success(getCoreVersion())
                }
                "requestVpnPermission" -> {
                    requestVpnPermission(result)
                }
                "copyLogsToClipboard" -> {
                    result.success(copyLogsToClipboard())
                }
                "getDeviceInfo" -> {
                    result.success(getDeviceInfo())
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
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun startCore(configPath: String?): Boolean {
        // TODO: 实现 Mihomo 核心启动
        return true
    }

    private fun stopCore(): Boolean {
        // TODO: 实现 Mihomo 核心停止
        return true
    }

    private fun startVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            startActivityForResult(intent, VPN_REQUEST_CODE)
            // Result will be handled in onActivityResult
            pendingVpnResult = result
        } else {
            // VPN permission already granted
            doStartVpn()
            result.success(true)
        }
    }

    private var pendingVpnResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == RESULT_OK) {
                doStartVpn()
                pendingVpnResult?.success(true)
            } else {
                pendingVpnResult?.success(false)
            }
            pendingVpnResult = null
        }
    }

    private fun doStartVpn() {
        val intent = Intent(this, VortexVpnService::class.java)
        intent.action = VortexVpnService.ACTION_START
        startService(intent)
    }

    private fun stopVpn(): Boolean {
        val intent = Intent(this, VortexVpnService::class.java)
        intent.action = VortexVpnService.ACTION_STOP
        startService(intent)
        return true
    }

    private fun setSystemProxy(enable: Boolean, port: Int): Boolean {
        // Android doesn't support system-wide proxy without root
        // VPN mode handles this
        return true
    }

    private fun getVpnState(): String {
        return VortexVpnService.getState()
    }

    private fun getCoreVersion(): String {
        // TODO: 从 Mihomo 核心获取版本
        return "unknown"
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            startActivityForResult(intent, VPN_REQUEST_CODE)
            pendingVpnResult = result
        } else {
            result.success(true)
        }
    }

    private fun copyLogsToClipboard(): Boolean {
        // TODO: 实现日志复制
        return true
    }

    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "model" to android.os.Build.MODEL,
            "manufacturer" to android.os.Build.MANUFACTURER,
            "version" to android.os.Build.VERSION.RELEASE,
            "sdk" to android.os.Build.VERSION.SDK_INT
        )
    }

    // 发送事件到 Flutter
    fun sendEvent(type: String, data: Any?) {
        eventSink?.success(mapOf(
            "type" to type,
            "data" to data
        ))
    }
}
