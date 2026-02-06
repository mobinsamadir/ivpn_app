package com.example.ivpn_new

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

class MyVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var libboxProcess: Process? = null
    private val isRunning = AtomicBoolean(false)

    companion object {
        const val VPN_NOTIFICATION_CHANNEL_ID = "ivpn_service_channel"
        const val VPN_NOTIFICATION_ID = 1
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.getStringExtra("action")
        val config = intent?.getStringExtra("config")

        if (action == ACTION_START && config != null) {
            startVpn(config)
        } else if (action == ACTION_STOP) {
            stopVpn()
        }

        return START_NOT_STICKY
    }

    private fun startVpn(configJson: String) {
        if (isRunning.get()) return
        isRunning.set(true)

        // Create notification channel for Android O+
        createNotificationChannel()
        
        // Start foreground service immediately
        startForeground(VPN_NOTIFICATION_ID, createNotification())

        try {
            // 1. Build VPN Interface
            val builder = Builder()
            builder.setSession("iVPN Connection")
            builder.addAddress("172.16.0.1", 24)
            builder.addRoute("0.0.0.0", 0)
            
            // Set MTU
            builder.setMtu(1500)
            
            // Set DNS (Optional - can be uncommented if needed)
            builder.addDnsServer("8.8.8.8")
            builder.addDnsServer("1.1.1.1")

            vpnInterface = builder.establish()

            if (vpnInterface == null) {
                stopVpn()
                return
            }

            // 2. Run Sing-box (libbox) logic here
            runSingBoxProcess(configJson)

        } catch (e: Exception) {
            e.printStackTrace()
            stopVpn()
        }
    }

    private fun runSingBoxProcess(configContent: String) {
        Thread {
            try {
                // Get app native library directory
                val nativeLibDir = applicationInfo.nativeLibraryDir
                val libboxPath = File(nativeLibDir, "libbox.so").absolutePath

                // Prepare config file safely
                val configDir = getExternalFilesDir(null)!! 
                val configFile = File(configDir, "config.json")
                configFile.writeText(configContent)

                // Build command
                val command = arrayOf(
                    libboxPath,
                    "run",
                    "-c", configFile.absolutePath,
                    "-D", configDir.absolutePath
                )

                val processBuilder = ProcessBuilder(*command)
                processBuilder.directory(configDir)
                processBuilder.redirectErrorStream(true)
                
                libboxProcess = processBuilder.start()

                // Wait for process to exit
                libboxProcess?.waitFor()

            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                // If process exits, stop VPN
                stopVpn()
            }
        }.start()
    }

    private fun stopVpn() {
        if (!isRunning.get()) return
        isRunning.set(false)
        
        try {
            libboxProcess?.destroy()
            libboxProcess = null
            
            vpnInterface?.close()
            vpnInterface = null
            
            stopForeground(true)
            stopSelf()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                VPN_NOTIFICATION_CHANNEL_ID,
                "iVPN Connection Status",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, VPN_NOTIFICATION_CHANNEL_ID)
            .setContentTitle("iVPN is Connected")
            .setContentText("Your traffic is secure")
            .setSmallIcon(R.mipmap.ic_launcher) // Correct Icon Usage
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
    }
}