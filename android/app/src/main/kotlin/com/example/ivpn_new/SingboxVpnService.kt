package com.example.ivpn_new

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
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

import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.WIFIState
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterface
import io.nekohasekai.libbox.Notification as LibboxNotification

class SingboxVpnService : VpnService(), PlatformInterface by StubPlatformInterface() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO + Job())

    companion object {
        const val VPN_NOTIFICATION_CHANNEL_ID = "ivpn_service_channel"
        const val VPN_NOTIFICATION_ID = 1
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"

        val isVpnRunning = AtomicBoolean(false)
        private val isTestRunning = AtomicBoolean(false)
        private val testMutex = Mutex()

        private fun validateAndResolveConfig(input: String, result: MethodChannel.Result?): String? {
             if (input.isBlank()) {
                 result?.let { r -> Handler(Looper.getMainLooper()).post { r.error("EMPTY_INPUT", "Config input is blank", null) } }
                 return null
             }

             if (input.startsWith("/")) {
                 val file = File(input)
                 if (!file.exists()) {
                     result?.let { r -> Handler(Looper.getMainLooper()).post { r.error("FILE_NOT_FOUND", "Config file not found at path: $input", null) } }
                     return null
                 }
                 try {
                     val content = file.readText()
                     if (content.isBlank()) {
                         result?.let { r -> Handler(Looper.getMainLooper()).post { r.error("EMPTY_CONFIG", "Config file is empty", null) } }
                         return null
                     }
                     return content
                 } catch (e: Exception) {
                     result?.let { r -> Handler(Looper.getMainLooper()).post { r.error("FILE_READ_ERROR", "Failed to read file: ${e.message}", null) } }
                     return null
                 }
             }
             return input
        }

        // --- NEW: Granular Control for Dart-driven Testing ---
        suspend fun startTestProxy(rawInput: String, tempDir: File, result: MethodChannel.Result?) = withContext(Dispatchers.IO) {
            if (isVpnRunning.get()) {
                println("❌ [Native] Cannot start Test Proxy: VPN is running")
                result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                return@withContext
            }

            if (!isTestRunning.compareAndSet(false, true)) {
                 println("❌ [Native] Cannot start Test Proxy: Another test is already running")
                 result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-2) } }
                 return@withContext
            }

            try {
                // STRICT VALIDATION
                val configJson = validateAndResolveConfig(rawInput, result)
                if (configJson == null) {
                    // Error already sent via result
                    isTestRunning.set(false)
                    return@withContext
                }

                val json = JSONObject(configJson)
                var socksPort = 0

                // 1. Try to use Port from Dart (Priority)
                if (json.has("inbounds")) {
                     val existingInbounds = json.getJSONArray("inbounds")
                     for (i in 0 until existingInbounds.length()) {
                         val inbound = existingInbounds.getJSONObject(i)
                         if (inbound.optString("type") == "socks" && inbound.has("listen_port")) {
                             socksPort = inbound.getInt("listen_port")
                             break
                         }
                     }
                }

                // 2. Fallback to Random Allocation
                if (socksPort <= 0) {
                    val socket = ServerSocket(0)
                    socksPort = socket.localPort
                    socket.close()

                    val inbounds = JSONArray()
                    val socksInbound = JSONObject()
                    socksInbound.put("type", "socks")
                    socksInbound.put("tag", "socks-in")
                    socksInbound.put("listen", "127.0.0.1")
                    socksInbound.put("listen_port", socksPort)
                    inbounds.put(socksInbound)
                    json.put("inbounds", inbounds)
                }

                if (!json.has("outbounds")) {
                    isTestRunning.set(false)
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-3) } }
                    return@withContext
                }

                if (json.has("log")) {
                     val logObj = json.getJSONObject("log")
                     logObj.put("level", "error")
                }

                val testConfigStr = json.toString()
                val testConfigFile = File(tempDir, "test_proxy_${System.currentTimeMillis()}.json")
                testConfigFile.writeText(testConfigStr)

                // SAFE CALL to Libbox - pass JSON content string
                Libbox.newService(testConfigStr, StubPlatformInterface())
                delay(200)

                result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(socksPort) } }

            } catch (e: Exception) {
                e.printStackTrace()
                isTestRunning.set(false)
                try { Libbox.newService("", StubPlatformInterface()) } catch (_: Exception) {}
                result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-4) } }
            }
        }

        suspend fun stopTestProxy() = withContext(Dispatchers.IO) {
            if (isTestRunning.get()) {
                try {
                    Libbox.newService("", StubPlatformInterface())
                } catch (e: Exception) {
                    e.printStackTrace()
                } finally {
                    isTestRunning.set(false)
                }
            }
        }

        suspend fun measurePing(rawInput: String, tempDir: File, result: MethodChannel.Result?) = withContext(Dispatchers.IO) {
            if (isVpnRunning.get()) {
                result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                return@withContext
            }
            if (!isTestRunning.compareAndSet(false, true)) {
                result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                return@withContext
            }

            try {
                // STRICT VALIDATION
                val configJson = validateAndResolveConfig(rawInput, result)
                if (configJson == null) {
                     // Error already sent
                     isTestRunning.set(false)
                     return@withContext
                }

                val socket = ServerSocket(0)
                val socksPort = socket.localPort
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
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                    return@withContext
                }

                val testConfigFile = File(tempDir, "test_${System.currentTimeMillis()}.json")
                testConfigFile.writeText(json.toString())

                // SAFE CALL - pass JSON content string
                Libbox.newService(json.toString(), StubPlatformInterface())
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

                response.close()

                if (response.isSuccessful || response.code == 204) {
                    val ping = (endTime - startTime).toInt()
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(ping) } }
                } else {
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                }

            } catch (e: Exception) {
                result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
            } finally {
                try { Libbox.newService("", StubPlatformInterface()) } catch (_: Exception) {}
                isTestRunning.set(false)
            }
        }
    }

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

    private fun startVpn(rawInput: String) {
        if (isVpnRunning.get()) return

        if (isTestRunning.get()) {
             try { Libbox.newService("", StubPlatformInterface()) } catch (_: Exception) {}
             isTestRunning.set(false)
        }

        isVpnRunning.set(true)
        createNotificationChannel()
        startForeground(VPN_NOTIFICATION_ID, createNotification())

        serviceScope.launch {
            try {
                // STRICT VALIDATION (No result object available)
                val configJson = validateAndResolveConfig(rawInput, null)

                if (configJson == null) {
                    MainActivity.sendVpnStatus("ERROR: INVALID_CONFIG")
                    stopVpn()
                    return@launch
                }

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

                // SAFE CALL - pass JSON content string
                Libbox.newService(jsonObject.toString(), this@SingboxVpnService)

                // CRITICAL FIX: Broadcast "CONNECTED" State to Dart
                MainActivity.sendVpnStatus("CONNECTED")

            } catch (e: Exception) {
                e.printStackTrace()
                // CRITICAL FIX: Broadcast "ERROR" State to Dart
                MainActivity.sendVpnStatus("ERROR")
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

            // CRITICAL FIX: Broadcast "DISCONNECTED" State to Dart
            MainActivity.sendVpnStatus("DISCONNECTED")

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

class StubStringIterator : StringIterator {
    override fun next(): String = ""
    override fun hasNext(): Boolean = false
    override fun len(): Int = 0 
}

class StubNetworkInterfaceIterator : NetworkInterfaceIterator {
    override fun next(): NetworkInterface? = null
    override fun hasNext(): Boolean = false
}

class StubPlatformInterface : PlatformInterface {
    override fun autoDetectInterfaceControl(fd: Int) { }
    override fun openTun(options: TunOptions): Int = -1
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    override fun clearDNSCache() {}
    override fun readWIFIState(): WIFIState { 
        return WIFIState("wlan0", "00:00:00:00:00:00") 
    }
    override fun useProcFS(): Boolean = false
    override fun writeLog(message: String?) { }
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) { }
    override fun findConnectionOwner(ipProtocol: Int, sourceAddress: String?, sourcePort: Int, destinationAddress: String?, destinationPort: Int): Int = 0
    override fun getInterfaces(): NetworkInterfaceIterator { return StubNetworkInterfaceIterator() }
    override fun includeAllNetworks(): Boolean = false
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun packageNameByUid(uid: Int): String = "unknown"
    override fun uidByPackageName(packageName: String?): Int = 0
    override fun sendNotification(notification: LibboxNotification?) { } 
    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) { }
    override fun systemCertificates(): StringIterator { return StubStringIterator() }
    override fun underNetworkExtension(): Boolean = false
}
