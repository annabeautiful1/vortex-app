package com.vortex.vortex_app

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class VortexTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()

        val state = VortexVpnService.getState()

        if (state == "connected") {
            // 停止 VPN
            val intent = Intent(this, VortexVpnService::class.java)
            intent.action = VortexVpnService.ACTION_STOP
            startService(intent)
        } else if (state == "disconnected") {
            // 启动 VPN
            val intent = Intent(this, VortexVpnService::class.java)
            intent.action = VortexVpnService.ACTION_START
            startService(intent)
        }

        updateTile()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val state = VortexVpnService.getState()

        when (state) {
            "connected" -> {
                tile.state = Tile.STATE_ACTIVE
                tile.label = "Vortex: 已连接"
            }
            "connecting", "disconnecting" -> {
                tile.state = Tile.STATE_UNAVAILABLE
                tile.label = "Vortex: 处理中..."
            }
            else -> {
                tile.state = Tile.STATE_INACTIVE
                tile.label = "Vortex: 未连接"
            }
        }

        tile.updateTile()
    }
}
