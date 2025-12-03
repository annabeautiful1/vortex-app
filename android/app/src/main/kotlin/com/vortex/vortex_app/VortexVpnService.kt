package com.vortex.vortex_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat

class VortexVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.vortex.vpn.START"
        const val ACTION_STOP = "com.vortex.vpn.STOP"
        const val NOTIFICATION_CHANNEL_ID = "vortex_vpn_channel"
        const val NOTIFICATION_ID = 1

        private var currentState = "disconnected"

        fun getState(): String = currentState
    }

    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startVpn()
            ACTION_STOP -> stopVpn()
        }
        return START_STICKY
    }

    private fun startVpn() {
        currentState = "connecting"

        // 创建 VPN 接口
        val builder = Builder()
            .setSession("Vortex VPN")
            .setMtu(1500)
            .addAddress("10.0.0.2", 32)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("8.8.8.8")
            .addDnsServer("8.8.4.4")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        // 排除本应用
        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {
            // Ignore
        }

        vpnInterface = builder.establish()

        if (vpnInterface != null) {
            currentState = "connected"
            startForeground(NOTIFICATION_ID, createNotification())

            // TODO: 将 VPN 接口传递给 Mihomo 核心
            // 通过 JNI 或 Socket 与核心通信
        } else {
            currentState = "disconnected"
            stopSelf()
        }
    }

    private fun stopVpn() {
        currentState = "disconnecting"

        vpnInterface?.close()
        vpnInterface = null

        currentState = "disconnected"
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Vortex VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Vortex VPN 服务通知"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Vortex VPN")
            .setContentText("已连接")
            .setSmallIcon(R.drawable.ic_vpn_key)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }
}
