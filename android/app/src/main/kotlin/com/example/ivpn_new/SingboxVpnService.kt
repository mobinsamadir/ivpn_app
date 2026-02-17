package com.example.ivpn_new

// Android Imports
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

// --- LIBBOX IMPORTS (CRITICAL FIXES) ---
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.WIFIState
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterface
// Alias to avoid conflict with android.app.Notification
import io.nekohasekai.libbox.Notification as LibboxNotification

class SingboxVpnService : VpnService(), PlatformInterface by StubPlatformInterface() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO + Job())

    companion object {
        const val VPN_NOTIFICATION_CHANNEL_ID = "ivpn_service_channel"
        const val VPN_NOTIFICATION_ID = 1
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"

        private val testMutex = Mutex()
        val isVpnRunning = AtomicBoolean(false)

        suspend fun measurePing(configJson: String, tempDir: File): Int = withContext(Dispatchers.IO) {
            // Prevent testing if VPN is running to avoid conflicts
            if (isVpnRunning.get()) {
                return@withContext -1
            }

            testMutex.withLock {
                var socksPort = 0
                try {
                    val socket = ServerSocket(0)
                    socksPort = socket.localPort
                    socket.close()

                    val json = JSONObject(configJson)
                    val inbounds = JSONArray()
                    val socksInbound = JSONObject()
                    socksInbound.put("type", "socks")
                    socksInbound.put("tag", "socks-in")
                    socksInbound.put("listen", "127.0.0.1")
                    socksInbound.put("listen_port", socksPort)
                    inbounds.put(socksInbound)
                    json.put("inbounds", inbounds)

                    if (!json.has("outbounds")) {
                        return@withLock -1
                    }

                    val testConfigStr = json.toString()
                    val testConfigFile = File(tempDir, "test_${System.currentTimeMillis()}.json")
                    testConfigFile.writeText(testConfigStr)

                    // Use StubPlatformInterface for static context (Fixes crash)
                    Libbox.newService(testConfigFile.absolutePath, StubPlatformInterface())

                    delay(500)

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
                    try {
                        Libbox.newService("", StubPlatformInterface())
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }
    }

    // --- CRITICAL OVERRIDE FOR VPN TRAFFIC ---
    // Without this, the VPN connects but no data flows.
    override fun autoDetectInterfaceControl(fd: Int) {
        this.protect(fd)
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

                // Pass 'this' as PlatformInterface (Required by new Libbox API)
                Libbox.newService(configFile.absolutePath, this@SingboxVpnService)

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
            Libbox.newService("", this)
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

// ==========================================
//           COMPLETE STUB IMPLEMENTATIONS
// ==========================================

// 1. String Iterator Stub
class StubStringIterator : StringIterator {
    override fun next(): String = ""
    override fun hasNext(): Boolean = false
    override fun len(): Int = 0 // Fixed: Added missing method
}

// 2. Network Interface Iterator Stub
class StubNetworkInterfaceIterator : NetworkInterfaceIterator {
    override fun next(): NetworkInterface? = null
    override fun hasNext(): Boolean = false
}

// 3. Main Platform Stub (Implementing ALL missing methods from logs)
class StubPlatformInterface : PlatformInterface {
    
    // Original methods
    override fun autoDetectInterfaceControl(fd: Int) { }
    override fun openTun(options: TunOptions): Int = -1
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    override fun clearDNSCache() {}

    // WIFI State (Fixed types: Returns Object, Not String)
    override fun readWIFIState(): WIFIState { return WIFIState() }
    override fun writeWIFIState(state: WIFIState?) { }

    // NEWLY ADDED METHODS (Fixes "Abstract member not implemented" errors)
    override fun useProcFS(): Boolean = false
    override fun writeLog(message: String?) { }
    
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) { }
    
    override fun findConnectionOwner(ipProtocol: Int, sourceAddress: String?, sourcePort: Int, destinationAddress: String?, destinationPort: Int): Int = 0
    
    override fun getInterfaces(): NetworkInterfaceIterator { return StubNetworkInterfaceIterator() }
    
    override fun includeAllNetworks(): Boolean = false
    
    override fun localDNSTransport(): LocalDNSTransport? = null
    
    override fun packageNameByUid(uid: Int): String = "unknown"
    
    override fun uidByPackageName(packageName: String?): Int = 0
    
    // Uses aliased import to avoid conflict with android.app.Notification
    override fun sendNotification(notification: LibboxNotification?) { } 
    
    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) { }
    
    override fun systemCertificates(): StringIterator { return StubStringIterator() }
    
    override fun underNetworkExtension(): Boolean = false
}
