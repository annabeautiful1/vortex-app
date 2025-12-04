package com.vortex.vortex_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "vortex_prefs"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON" ||
            intent.action == "com.htc.intent.action.QUICKBOOT_POWERON") {

            Log.i(TAG, "Boot completed received")

            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val autoStart = prefs.getBoolean("auto_start", false)
            val autoConnect = prefs.getBoolean("auto_connect", false)

            if (autoStart || autoConnect) {
                Log.i(TAG, "Auto-start enabled, checking VPN permission...")

                // Check if VPN permission is granted
                val vpnIntent = VpnService.prepare(context)
                if (vpnIntent == null) {
                    // VPN permission already granted, start VPN service
                    Log.i(TAG, "Starting VPN service on boot")
                    startVpnService(context)
                } else {
                    // VPN permission not granted, can't start automatically
                    Log.w(TAG, "VPN permission not granted, cannot auto-start")
                }
            } else {
                Log.i(TAG, "Auto-start not enabled")
            }
        }
    }

    private fun startVpnService(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val configPath = prefs.getString("current_config_path", null)

            if (configPath == null) {
                Log.w(TAG, "No config path found, cannot start VPN")
                return
            }

            val serviceIntent = Intent(context, VortexVpnService::class.java).apply {
                action = VortexVpnService.ACTION_START
                putExtra(VortexVpnService.EXTRA_CONFIG_PATH, configPath)
                putExtra(VortexVpnService.EXTRA_WORK_DIR, context.filesDir.absolutePath)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }

            Log.i(TAG, "VPN service started on boot")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN service on boot", e)
        }
    }
}
