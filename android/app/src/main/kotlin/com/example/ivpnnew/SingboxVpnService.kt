package com.example.ivpnnew

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
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ServerSocket
import java.util.concurrent.TimeUnit
import io.nekohasekai.libbox.Notification as LibboxNotification

class SingboxVpnService :
    VpnService(),
    PlatformInterface by StubPlatformInterface() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var mainServer: io.nekohasekai.libbox.CommandServer? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO + Job())

    companion object {
        const val VPN_NOTIFICATION_CHANNEL_ID = "ivpn_service_channel"
        const val VPN_NOTIFICATION_ID = 1
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"

        var isVpnRunning = false
        val nativeCallMutex = Mutex()
        private var testServer: io.nekohasekai.libbox.CommandServer? = null

        private suspend fun closeTestServerUnlocked() {
            if (testServer != null) {
                try {
                    android.util.Log.d("NativeVpnLifecycle", "Closing existing testServer...")
                    testServer?.close()
                    testServer = null
                    android.util.Log.d("NativeVpnLifecycle", "testServer successfully closed.")
                    delay(100) // Ensure OS cleans up socket/goroutine
                } catch (e: Throwable) {
                    android.util.Log.e("NativeVpnLifecycle", "Error closing testServer: ${e.message}")
                    e.printStackTrace()
                }
            }
        }

        private fun getValidJsonConfig(
            input: String,
            deleteAfterRead: Boolean = false,
        ): String {
            val trimmed = input.trim()
            if (trimmed.startsWith("{")) {
                return trimmed // Already a valid JSON string
            }

            // Otherwise, it must be a file path
            val file = java.io.File(trimmed)
            if (!file.exists()) {
                throw IllegalArgumentException("File does not exist: $trimmed")
            }

            val content = file.readText().trim()
            if (deleteAfterRead) {
                try {
                    file.delete()
                } catch (e: Throwable) {
                    e.printStackTrace()
                }
            }
            if (content.isEmpty()) {
                throw IllegalArgumentException("File is empty: $trimmed")
            }
            if (!content.startsWith("{")) {
                throw IllegalArgumentException("File content is not valid JSON")
            }

            return content
        }

        // --- NEW: Granular Control for Dart-driven Testing ---
        suspend fun startTestProxy(
            rawInput: String,
            tempDir: File,
            result: MethodChannel.Result?,
        ) = withContext(Dispatchers.IO) {
            nativeCallMutex.withLock {
                if (isVpnRunning) {
                    println("❌ [Native] Cannot start Test Proxy: VPN is running")
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                    return@withContext
                }

                // Forcefully cancel any ongoing test to prevent queuing and await its termination
                closeTestServerUnlocked()

                try {
                    // STRICT VALIDATION
                    val configJson: String
                    try {
                        configJson = getValidJsonConfig(rawInput, true)
                    } catch (e: Throwable) {
                        // Send error to Flutter immediately on the Main Thread
                        result?.let { r -> Handler(Looper.getMainLooper()).post { r.error("CONFIG_ERROR", e.message, null) } }
                        return@withContext // EXIT the coroutine. DO NOT proceed to Libbox!
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
                        result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-3) } }
                        return@withContext
                    }

                    if (json.has("log")) {
                        val logObj = json.getJSONObject("log")
                        logObj.put("level", "error")
                    }


                    try {
                        // SAFE CALL to Libbox - pass JSON content string
                        val server =
                            try {
                                val options = io.nekohasekai.libbox.SetupOptions()
                                options.setBasePath(tempDir.absolutePath)
                                options.setWorkingPath(tempDir.absolutePath)
                                options.setTempPath(tempDir.absolutePath)
                                Libbox.setup(options)
                                Libbox.newCommandServer(StubCommandServerHandler(), StubPlatformInterface())
                            } catch (e: Throwable) {
                                e.printStackTrace()
                                result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                                return@withContext
                            }

                        try {
                            server?.startOrReloadService(json.toString(), null)
                            testServer = server
                        } catch (e: Throwable) {
                            server?.close()
                            e.printStackTrace()
                            result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                            return@withContext
                        }
                        delay(200)

                        result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(socksPort) } }
                    } finally {
                        // Removed file cleanup as no file is written
                    }
                } catch (e: Throwable) {
                    e.printStackTrace()
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-4) } }
                }
            }
        }

        suspend fun stopTestProxy() =
            withContext(Dispatchers.IO) {
                nativeCallMutex.withLock {
                    try {
                        closeTestServerUnlocked()
                    } catch (e: Throwable) {
                        e.printStackTrace()
                    }
                }
            }

        suspend fun measurePing(
            rawInput: String,
            tempDir: File,
            result: MethodChannel.Result?,
        ) = withContext(Dispatchers.IO) {
            nativeCallMutex.withLock {
                if (isVpnRunning) {
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                    return@withContext
                }
                // Forcefully cancel any ongoing test and await its termination
                closeTestServerUnlocked()

                try {
                    // STRICT VALIDATION
                    val configJson: String
                    try {
                        configJson = getValidJsonConfig(rawInput, true)
                    } catch (e: Throwable) {
                        // Send error to Flutter immediately on the Main Thread
                        result?.let { r -> Handler(Looper.getMainLooper()).post { r.error("CONFIG_ERROR", e.message, null) } }
                        return@withContext // EXIT the coroutine. DO NOT proceed to Libbox!
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


                    try {
                        closeTestServerUnlocked()

                        // SAFE CALL - pass JSON content string
                        val newTestServer =
                            try {
                                val options = io.nekohasekai.libbox.SetupOptions()
                                options.setBasePath(tempDir.absolutePath)
                                options.setWorkingPath(tempDir.absolutePath)
                                options.setTempPath(tempDir.absolutePath)
                                Libbox.setup(options)
                                Libbox.newCommandServer(StubCommandServerHandler(), StubPlatformInterface())
                            } catch (e: Throwable) {
                                e.printStackTrace()
                                MainActivity.sendVpnStatus("ERROR: TEST_START_FAILED - ${e.message}")
                                result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                                return@withContext
                            }

                        try {
                            newTestServer?.startOrReloadService(json.toString(), null)
                            testServer = newTestServer
                        } catch (e: Throwable) {
                            newTestServer?.close()
                            e.printStackTrace()
                            MainActivity.sendVpnStatus("ERROR: TEST_START_FAILED - ${e.message}")
                            result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                            return@withContext
                        }
                        delay(500)

                        val client =
                            OkHttpClient
                                .Builder()
                                .connectTimeout(3, TimeUnit.SECONDS)
                                .readTimeout(3, TimeUnit.SECONDS)
                                .proxy(Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", socksPort)))
                                .build()

                        val request =
                            Request
                                .Builder()
                                .url("http://www.google.com/generate_204")
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
                    } finally {
                        // Removed file cleanup as no file is written
                    }
                } catch (e: Throwable) {
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                } finally {
                    // test server close handled normally
                }
            }
        }
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        this.protect(fd)
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val action = intent?.getStringExtra("action")
        val config = intent?.getStringExtra("config")

        serviceScope.launch {
            if (action == ACTION_START && config != null) {
                startVpn(config)
            } else if (action == ACTION_STOP) {
                stopVpn()
            }
        }

        return START_NOT_STICKY
    }

    private suspend fun startVpn(rawInput: String) {
        nativeCallMutex.withLock {
            if (isVpnRunning) return

            isVpnRunning = true

            createNotificationChannel()
            startForeground(VPN_NOTIFICATION_ID, createNotification())

            try {
                // Wait for any running test to finish closing before starting main VPN
                closeTestServerUnlocked()

                // STRICT VALIDATION
                val configJson: String
                try {
                    configJson = getValidJsonConfig(rawInput, true)
                    if (configJson.isNullOrBlank()) {
                        throw IllegalArgumentException("Config string is null or empty")
                    }
                } catch (e: Throwable) {
                    MainActivity.sendVpnStatus("ERROR: CONFIG_ERROR - ${e.message}")
                    stopVpnInternal()
                    return
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
                    stopVpnInternal()
                    return
                }

                val fd = vpnInterface!!.fd
                val configDir = getExternalFilesDir(null) ?: filesDir

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

                // SAFE CALL - pass JSON content string
                try {
                    val options = io.nekohasekai.libbox.SetupOptions()
                    options.setBasePath(configDir.absolutePath)
                    options.setWorkingPath(configDir.absolutePath)
                    options.setTempPath(configDir.absolutePath)
                    Libbox.setup(options)
                    mainServer = Libbox.newCommandServer(StubCommandServerHandler(), this@SingboxVpnService)
                    mainServer?.startOrReloadService(jsonObject.toString(), null)
                } catch (e: Throwable) {
                    e.printStackTrace()
                    android.util.Log.e("NativeVpnLifecycle", "StartOrReloadService Error: ${e.message}")
                    MainActivity.sendVpnStatus("ERROR: START_FAILED - ${e.message}")
                    stopVpnInternal()
                    return
                }

                // CRITICAL FIX: Broadcast "CONNECTED" State to Dart
                MainActivity.sendVpnStatus("CONNECTED")
            } catch (e: Throwable) {
                e.printStackTrace()
                // CRITICAL FIX: Broadcast "ERROR" State to Dart
                MainActivity.sendVpnStatus("ERROR")
                stopVpnInternal()
            }
        }
    }

    private suspend fun stopVpn() {
        nativeCallMutex.withLock {
            stopVpnInternal()
        }
    }

    private fun stopVpnInternal() {
        if (!isVpnRunning) return
        isVpnRunning = false
        android.util.Log.d("NativeVpnLifecycle", "stopVpnInternal called")

        try {
            mainServer?.close()
            mainServer = null
            vpnInterface?.close()
            vpnInterface = null

            stopForeground(true)
            stopSelf()

            // CRITICAL FIX: Broadcast "DISCONNECTED" State to Dart
            MainActivity.sendVpnStatus("DISCONNECTED")
            android.util.Log.d("NativeVpnLifecycle", "stopVpnInternal completed successfully")
        } catch (e: Throwable) {
            android.util.Log.e("NativeVpnLifecycle", "stopVpnInternal error: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel =
                NotificationChannel(
                    VPN_NOTIFICATION_CHANNEL_ID,
                    "iVPN Connection Status",
                    NotificationManager.IMPORTANCE_LOW,
                )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                notificationIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        return NotificationCompat
            .Builder(this, VPN_NOTIFICATION_CHANNEL_ID)
            .setContentTitle("iVPN is Connected")
            .setContentText("Your traffic is secure")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    override fun onRevoke() {
        super.onRevoke()
        android.util.Log.d("NativeVpnLifecycle", "onRevoke called by OS")
        MainActivity.sendVpnStatus("ERROR: REVOKED")
        stopVpnInternal()
    }

    override fun onDestroy() {
        super.onDestroy()
        android.util.Log.d("NativeVpnLifecycle", "onDestroy called")
        runBlocking {
            stopVpn()
            nativeCallMutex.withLock {
                closeTestServerUnlocked()
            }
        }
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

    override fun readWIFIState(): WIFIState = WIFIState("wlan0", "00:00:00:00:00:00")

    override fun useProcFS(): Boolean = false

    fun writeLog(message: String?) {
        MainActivity.sendVpnStatus(message ?: "")
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) { }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String?,
        sourcePort: Int,
        destinationAddress: String?,
        destinationPort: Int,
    ): io.nekohasekai.libbox.ConnectionOwner? = null

    override fun getInterfaces(): NetworkInterfaceIterator = StubNetworkInterfaceIterator()

    override fun includeAllNetworks(): Boolean = false

    override fun localDNSTransport(): LocalDNSTransport? = null

    fun packageNameByUid(uid: Int): String = "unknown"

    fun uidByPackageName(packageName: String?): Int = 0

    override fun sendNotification(notification: LibboxNotification?) { }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) { }

    override fun systemCertificates(): StringIterator = StubStringIterator()

    override fun underNetworkExtension(): Boolean = false
}

class StubCommandServerHandler : io.nekohasekai.libbox.CommandServerHandler {
    override fun getSystemProxyStatus(): io.nekohasekai.libbox.SystemProxyStatus? = null

    override fun serviceReload() {}

    override fun serviceStop() {}

    override fun setSystemProxyEnabled(enabled: Boolean) {}

    override fun writeDebugMessage(message: String?) {}
}
