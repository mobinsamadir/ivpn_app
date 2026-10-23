package com.ivpn_new

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class VpnTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()
        val tile = qsTile ?: return

        if (SingboxVpnService.isVpnRunning) {
            // Disconnect immediately
            tile.state = Tile.STATE_INACTIVE
            tile.label = "iVPN"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = "Disconnecting..."
            }
            tile.updateTile()

            val stopIntent = Intent(this, SingboxVpnService::class.java).apply {
                putExtra("action", SingboxVpnService.ACTION_STOP)
            }
            startService(stopIntent)
        } else {
            // Check if VPN permission is granted
            val prepareIntent = VpnService.prepare(this)
            val prefs = getSharedPreferences("ivpn_prefs", MODE_PRIVATE)
            val lastConfig = prefs.getString("last_vpn_config", null)

            if (prepareIntent == null && !lastConfig.isNullOrBlank()) {
                // Connect with last saved configuration
                tile.state = Tile.STATE_ACTIVE
                tile.label = "iVPN"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = "Connecting..."
                }
                tile.updateTile()

                val startIntent = Intent(this, SingboxVpnService::class.java).apply {
                    putExtra("action", SingboxVpnService.ACTION_START)
                    putExtra("config", lastConfig)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(startIntent)
                } else {
                    startService(startIntent)
                }
            } else {
                // VPN permission needed or no configuration saved yet -> open MainActivity
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                if (launchIntent != null) {
                    if (Build.VERSION.SDK_INT >= 34) {
                        val pendingIntent = PendingIntent.getActivity(
                            this,
                            0,
                            launchIntent,
                            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                        )
                        startActivityAndCollapse(pendingIntent)
                    } else {
                        @Suppress("DEPRECATION")
                        startActivityAndCollapse(launchIntent)
                    }
                }
            }
        }
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        val isRunning = SingboxVpnService.isVpnRunning

        tile.state = if (isRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "iVPN"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val server = SingboxVpnService.currentServerName
            tile.subtitle = if (isRunning) {
                if (server.isNotBlank()) "Connected ($server)" else "Connected"
            } else {
                "Disconnected"
            }
        }
        tile.icon = Icon.createWithResource(this, R.mipmap.ic_launcher)
        tile.updateTile()
    }
}
