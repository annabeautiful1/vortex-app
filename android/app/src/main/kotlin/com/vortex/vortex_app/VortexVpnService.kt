package com.vortex.vortex_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.vortex.vortex_app.core.MihomoCore
import kotlinx.coroutines.*
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class VortexVpnService : VpnService(), MihomoCore.CoreStateListener {

    companion object {
        private const val TAG = "VortexVpnService"

        const val ACTION_START = "com.vortex.vpn.START"
        const val ACTION_STOP = "com.vortex.vpn.STOP"
        const val ACTION_RELOAD = "com.vortex.vpn.RELOAD"

        const val EXTRA_CONFIG_PATH = "config_path"
        const val EXTRA_WORK_DIR = "work_dir"

        const val NOTIFICATION_CHANNEL_ID = "vortex_vpn_channel"
        const val NOTIFICATION_ID = 1

        private var currentState = "disconnected"
        private var instance: VortexVpnService? = null

        fun getState(): String = currentState

        fun getInstance(): VortexVpnService? = instance

        // Traffic stats
        var totalUpload: Long = 0
            private set
        var totalDownload: Long = 0
            private set
        var uploadSpeed: Long = 0
            private set
        var downloadSpeed: Long = 0
            private set
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var configPath: String? = null
    private var workDir: String? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // TUN device reader/writer threads
    private var tunReadJob: Job? = null
    private var tunWriteJob: Job? = null

    // State change listener (for MainActivity)
    var stateChangeListener: ((String, Any?) -> Unit)? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        MihomoCore.setStateListener(this)

        // Initialize core
        MihomoCore.init(this)

        Log.i(TAG, "VortexVpnService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                configPath = intent.getStringExtra(EXTRA_CONFIG_PATH)
                workDir = intent.getStringExtra(EXTRA_WORK_DIR)
                startVpn()
            }
            ACTION_STOP -> {
                stopVpn()
            }
            ACTION_RELOAD -> {
                val newConfigPath = intent.getStringExtra(EXTRA_CONFIG_PATH)
                if (newConfigPath != null) {
                    scope.launch {
                        reloadConfig(newConfigPath)
                    }
                }
            }
        }
        return START_STICKY
    }

    private fun startVpn() {
        currentState = "connecting"
        notifyStateChange("connecting")

        // Start as foreground service first
        startForeground(NOTIFICATION_ID, createNotification("Connecting..."))

        scope.launch {
            try {
                // Start Mihomo core first
                val coreStarted = withContext(Dispatchers.IO) {
                    configPath?.let { path ->
                        MihomoCore.start(this@VortexVpnService, path)
                    } ?: false
                }

                if (!coreStarted) {
                    Log.e(TAG, "Failed to start Mihomo core")
                    currentState = "error"
                    notifyStateChange("error")
                    stopSelf()
                    return@launch
                }

                // Wait for core to be ready
                delay(500)

                // Create VPN interface
                withContext(Dispatchers.Main) {
                    createVpnInterface()
                }

                if (vpnInterface != null) {
                    currentState = "connected"
                    notifyStateChange("connected")
                    updateNotification("Connected")

                    // Start TUN forwarding (if needed - Mihomo handles this via TUN mode in config)
                    startTunForwarding()

                    Log.i(TAG, "VPN started successfully")
                } else {
                    Log.e(TAG, "Failed to establish VPN interface")
                    currentState = "error"
                    notifyStateChange("error")
                    MihomoCore.stop()
                    stopSelf()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error starting VPN", e)
                currentState = "error"
                notifyStateChange("error")
                MihomoCore.stop()
                stopSelf()
            }
        }
    }

    private fun createVpnInterface() {
        try {
            val builder = Builder()
                .setSession("Vortex VPN")
                .setMtu(9000)
                // TUN address - must match Mihomo config
                .addAddress("172.19.0.1", 30)
                // Route all traffic through VPN
                .addRoute("0.0.0.0", 0)
                // DNS servers
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")

            // Android 10+ features
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            // Bypass apps (optional - can be configured)
            try {
                // Don't route our own app through VPN
                builder.addDisallowedApplication(packageName)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to add disallowed application", e)
            }

            vpnInterface = builder.establish()

            if (vpnInterface != null) {
                Log.i(TAG, "VPN interface established: fd=${vpnInterface?.fd}")

                // Protect the Mihomo socket
                protectMihomoSockets()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create VPN interface", e)
            vpnInterface = null
        }
    }

    private fun protectMihomoSockets() {
        // Mihomo handles socket protection internally when running as TUN
        // This is mainly for reference
    }

    private fun startTunForwarding() {
        // Mihomo handles TUN read/write internally when configured with tun.device
        // This is a placeholder for custom implementation if needed

        /*
        val fd = vpnInterface?.fd ?: return

        tunReadJob = scope.launch {
            // Read from TUN device and forward to Mihomo
        }

        tunWriteJob = scope.launch {
            // Read from Mihomo and write to TUN device
        }
        */
    }

    private fun stopTunForwarding() {
        tunReadJob?.cancel()
        tunWriteJob?.cancel()
        tunReadJob = null
        tunWriteJob = null
    }

    private fun stopVpn() {
        currentState = "disconnecting"
        notifyStateChange("disconnecting")

        scope.launch {
            // Stop TUN forwarding
            stopTunForwarding()

            // Stop Mihomo core
            MihomoCore.stop()

            // Close VPN interface
            withContext(Dispatchers.Main) {
                try {
                    vpnInterface?.close()
                    vpnInterface = null
                } catch (e: Exception) {
                    Log.e(TAG, "Error closing VPN interface", e)
                }
            }

            currentState = "disconnected"
            notifyStateChange("disconnected")

            // Reset traffic stats
            totalUpload = 0
            totalDownload = 0
            uploadSpeed = 0
            downloadSpeed = 0

            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()

            Log.i(TAG, "VPN stopped")
        }
    }

    private suspend fun reloadConfig(newConfigPath: String) {
        val success = MihomoCore.reloadConfig(newConfigPath)
        if (success) {
            configPath = newConfigPath
            Log.i(TAG, "Config reloaded: $newConfigPath")
        } else {
            Log.e(TAG, "Failed to reload config")
        }
    }

    // MihomoCore.CoreStateListener implementation
    override fun onStateChanged(state: String) {
        currentState = state
        notifyStateChange(state)
        updateNotification(when(state) {
            "connected" -> "Connected"
            "connecting" -> "Connecting..."
            "disconnecting" -> "Disconnecting..."
            else -> "Disconnected"
        })
    }

    override fun onTrafficUpdate(upload: Long, download: Long, upSpeed: Long, downSpeed: Long) {
        totalUpload = upload
        totalDownload = download
        uploadSpeed = upSpeed
        downloadSpeed = downSpeed

        // Notify Flutter
        stateChangeListener?.invoke("traffic_update", mapOf(
            "upload" to upload,
            "download" to download,
            "uploadSpeed" to upSpeed,
            "downloadSpeed" to downSpeed
        ))
    }

    override fun onLog(message: String) {
        stateChangeListener?.invoke("log", message)
    }

    override fun onError(error: String) {
        Log.e(TAG, "Core error: $error")
        stateChangeListener?.invoke("error", error)
    }

    private fun notifyStateChange(state: String) {
        stateChangeListener?.invoke("vpn_state_changed", state)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Vortex VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Vortex VPN service notification"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(status: String): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Stop action
        val stopIntent = Intent(this, VortexVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Vortex VPN")
            .setContentText(status)
            .setSmallIcon(R.drawable.ic_vpn_key)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", stopPendingIntent)
            .build()
    }

    private fun updateNotification(status: String) {
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, createNotification(status))
    }

    override fun onDestroy() {
        instance = null
        scope.cancel()
        MihomoCore.setStateListener(null)
        stopVpn()
        super.onDestroy()
        Log.i(TAG, "VortexVpnService destroyed")
    }

    override fun onRevoke() {
        Log.i(TAG, "VPN permission revoked")
        stopVpn()
        super.onRevoke()
    }
}
