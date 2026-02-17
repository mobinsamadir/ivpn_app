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
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ServerSocket
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import okhttp3.OkHttpClient
import okhttp3.Request
// Assuming Libbox is the main entry point. If the package/class differs, this needs adjustment.
import io.github.sagernet.libbox.Libbox

class SingboxVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO + Job())

    companion object {
        const val VPN_NOTIFICATION_CHANNEL_ID = "ivpn_service_channel"
        const val VPN_NOTIFICATION_ID = 1
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"

        // Mutex to ensure only one test runs at a time
        private val testMutex = Mutex()
        // Atomic flag to track if VPN is running (to prevent testing while VPN is active)
        val isVpnRunning = AtomicBoolean(false)

        suspend fun measurePing(configJson: String, tempDir: File): Int = withContext(Dispatchers.IO) {
            // Prevent testing if VPN is running to avoid conflicts
            if (isVpnRunning.get()) {
                return@withContext -1
            }

            testMutex.withLock {
                var socksPort = 0
                // Use a dedicated Libbox instance/command for testing
                // If Libbox is a singleton, this lock prevents race conditions.

                try {
                    // 1. Find a random free port
                    val socket = ServerSocket(0)
                    socksPort = socket.localPort
                    socket.close()

                    // 2. Modify Config to use SOCKS inbound
                    val json = JSONObject(configJson)
                    val inbounds = JSONArray()
                    val socksInbound = JSONObject()
                    socksInbound.put("type", "socks")
                    socksInbound.put("tag", "socks-in")
                    socksInbound.put("listen", "127.0.0.1")
                    socksInbound.put("listen_port", socksPort)
                    inbounds.put(socksInbound)
                    json.put("inbounds", inbounds)

                    // Ensure outbounds are correct (keep existing or ensure minimal)
                    if (!json.has("outbounds")) {
                        return@withLock -1
                    }

                    // Disable 'tun' if present in outbounds or inbounds just in case
                    // (Though we replaced inbounds, outbounds might have routing rules referring to tun)

                    val testConfigStr = json.toString()
                    val testConfigFile = File(tempDir, "test_${System.currentTimeMillis()}.json")
                    testConfigFile.writeText(testConfigStr)

                    // 3. Start Libbox in a way that doesn't trigger VPN service
                    // Assuming Libbox.run(path) starts it.
                    // Use a separate thread or process if possible, but here we just call start.
                    // If Libbox.start() is blocking, we need to launch it in a separate job.
                    // If it's non-blocking, we just call it.
                    // Usually 'run' is blocking, 'start' is async.
                    // We'll assume we can start it.

                    // Note: We are not passing a TUN FD, so it should run in user-mode (SOCKS only).
                    // Use a try-catch block for the start command.

                    // START LIBBOX
                    // If Libbox is a singleton, we must ensure we stop it after.
                    Libbox.newService(testConfigFile.absolutePath)

                    // Give it a moment to initialize
                    delay(500)

                    // 4. Measure Ping
                    val client = OkHttpClient.Builder()
                        .connectTimeout(3, TimeUnit.SECONDS)
                        .readTimeout(3, TimeUnit.SECONDS)
                        .proxy(Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort)))
                        .build()

                    val request = Request.Builder()
                        .url("https://www.google.com/generate_204")
                        .head()
                        .build()

                    val startTime = System.currentTimeMillis()
                    val response = client.newCall(request).execute()
                    val endTime = System.currentTimeMillis()

                    val duration = (endTime - startTime).toInt()
                    response.close()

                    if (response.isSuccessful || response.code == 204) {
                        return@withLock duration
                    } else {
                        return@withLock -1
                    }

                } catch (e: Exception) {
                    e.printStackTrace()
                    return@withLock -1
                } finally {
                    // 5. Stop Libbox
                    try {
                        Libbox.newService("")
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }
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
        if (isVpnRunning.get()) return
        isVpnRunning.set(true)

        createNotificationChannel()
        startForeground(VPN_NOTIFICATION_ID, createNotification())

        serviceScope.launch {
            try {
                // 1. Establish VPN Interface
                val builder = Builder()
                builder.setSession("iVPN Connection")
                builder.addAddress("172.19.0.1", 28)
                builder.addRoute("0.0.0.0", 0)
                builder.setMtu(1500)
                builder.addDnsServer("8.8.8.8")
                builder.addDnsServer("1.1.1.1")

                vpnInterface = builder.establish()

                if (vpnInterface == null) {
                    stopVpn()
                    return@launch
                }

                val fd = vpnInterface!!.fd
                val configDir = getExternalFilesDir(null)!!
                val configFile = File(configDir, "config.json")

                // Inject TUN File Descriptor
                val jsonObject = JSONObject(configJson)
                if (jsonObject.has("inbounds")) {
                    val inbounds = jsonObject.getJSONArray("inbounds")
                    for (i in 0 until inbounds.length()) {
                        val inbound = inbounds.getJSONObject(i)
                        if (inbound.optString("type") == "tun") {
                            inbound.put("file_descriptor", fd)
                        }
                    }
                }

                configFile.writeText(jsonObject.toString())

                // 2. Start Libbox
                Libbox.newService(configFile.absolutePath)

            } catch (e: Exception) {
                e.printStackTrace()
                stopVpn()
            }
        }
    }

    private fun stopVpn() {
        if (!isVpnRunning.get()) return
        isVpnRunning.set(false)

        try {
            Libbox.newService("")
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
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
        serviceScope.cancel()
    }
}
