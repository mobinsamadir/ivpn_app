package com.ivpn_new

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
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
import io.nekohasekai.libbox.OverrideOptions
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
        const val LOW_TIME_CHANNEL_ID = "ivpn_low_time_channel"
        const val LOW_TIME_NOTIFICATION_ID = 99
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"
        const val ACTION_DISCONNECT = "disconnect"
        const val ACTION_SKIP_SERVER = "skip_server"

        @Volatile var currentServerName: String = ""
        @Volatile var currentRemainingTimeText: String = ""
        @Volatile var currentRemainingSeconds: Int = -1
        @Volatile var lastDownSpeed: Long = 0
        @Volatile var lastUpSpeed: Long = 0
        @Volatile var lastRx: Long = 0
        @Volatile var lastTx: Long = 0

        fun updateTraffic(rx: Long, tx: Long, downSpeed: Long, upSpeed: Long) {
            lastRx = rx
            lastTx = tx
            lastDownSpeed = downSpeed
            lastUpSpeed = upSpeed
            activeServiceInstance?.updateNotificationStats()
        }

        fun updateSessionMeta(serverName: String?, remainingTimeText: String?, remainingSeconds: Int) {
            if (serverName != null) currentServerName = serverName
            if (remainingTimeText != null) currentRemainingTimeText = remainingTimeText
            currentRemainingSeconds = remainingSeconds
            android.util.Log.d("NativeVpnLifecycle", "updateSessionMeta: server=$currentServerName, time=$currentRemainingTimeText, remainingSec=$remainingSeconds")
            activeServiceInstance?.updateNotificationStats()
            activeServiceInstance?.checkLowTimeAlert(remainingSeconds)
        }

        var isVpnRunning = false
        var isLibboxSetup = false
        val nativeCallMutex = Mutex()
        private var testServer: io.nekohasekai.libbox.CommandServer? = null
        private val libboxSetupLock = Any()

        fun ensureLibboxSetup(workingDir: File) {
            synchronized(libboxSetupLock) {
                if (isLibboxSetup) return
                val options = io.nekohasekai.libbox.SetupOptions()
                options.setBasePath(workingDir.absolutePath)
                options.setWorkingPath(workingDir.absolutePath)
                options.setTempPath(workingDir.absolutePath)
                Libbox.setup(options)
                isLibboxSetup = true
            }
        }

        @Volatile
        var activeServiceInstance: SingboxVpnService? = null

        fun forceStopVpnNow() {
            android.util.Log.d("NativeVpnLifecycle", "forceStopVpnNow called on companion object")
            activeServiceInstance?.forceStopVpnNowInternal()
        }

        private suspend fun closeTestServerUnlocked() {
            val serverToClose = testServer
            testServer = null
            if (serverToClose != null) {
                try {
                    android.util.Log.d("NativeVpnLifecycle", "[LIFECYCLE] STOP_STARTED: Closing existing testServer...")
                    try {
                        try {
                            serverToClose.javaClass.getMethod("serviceStop").invoke(serverToClose)
                        } catch (_: Throwable) {
                            serverToClose.closeService()
                        }
                    } catch (_: Throwable) {}
                    serverToClose.close()
                    android.util.Log.d("NativeVpnLifecycle", "[LIFECYCLE] DISPOSED: testServer successfully closed.")
                } catch (e: Throwable) {
                    android.util.Log.e("NativeVpnLifecycle", "Error closing testServer: ${e.message}")
                    e.printStackTrace()
                } finally {
                    delay(120) // Fast GC and OS socket release
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
            testId: String = "unknown",
            rawInput: String,
            tempDir: File,
            result: MethodChannel.Result?,
        ) = withContext(Dispatchers.IO) {
            nativeCallMutex.withLock {
                if (isVpnRunning) {
                    android.util.Log.e("NativeLifecycle", "[LIFECYCLE][$testId] ERROR: Cannot start Test Proxy: VPN is running")
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
                                ensureLibboxSetup(tempDir)
                                Libbox.newCommandServer(StubCommandServerHandler(), StubPlatformInterface())
                            } catch (e: Throwable) {
                                e.printStackTrace()
                                result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                                return@withContext
                            }

                        if (server == null) {
                            result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                            return@withContext
                        }

                        try {
                            server.startOrReloadService(json.toString(), OverrideOptions())
                            testServer = server
                        } catch (e: Throwable) {
                            try { server.close() } catch (ignored: Throwable) {}
                            e.printStackTrace()
                            result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                            return@withContext
                        }
                        delay(80)

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
                        android.util.Log.d("NativeVpnLifecycle", "[LIFECYCLE] CREATE_STARTED")
                        val newTestServer =
                            try {
                                ensureLibboxSetup(tempDir)
                                Libbox.newCommandServer(StubCommandServerHandler(), StubPlatformInterface())
                            } catch (e: Throwable) {
                                e.printStackTrace()
                                MainActivity.sendVpnStatus("ERROR: TEST_START_FAILED - ${e.message}")
                                result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                                return@withContext
                            }

                        if (newTestServer == null) {
                            result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                            return@withContext
                        }

                        try {
                            android.util.Log.d("NativeVpnLifecycle", "[LIFECYCLE] START_STARTED")
                            newTestServer.startOrReloadService(json.toString(), OverrideOptions())
                            android.util.Log.d("NativeVpnLifecycle", "[LIFECYCLE] RUNNING")
                            testServer = newTestServer
                        } catch (e: Throwable) {
                            try { newTestServer.close() } catch (ignored: Throwable) {}
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

    override fun onCreate() {
        super.onCreate()
        activeServiceInstance = this
        android.util.Log.d("NativeVpnLifecycle", "SingboxVpnService onCreate, activeInstance set")
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val action = intent?.getStringExtra("action")
        val config = intent?.getStringExtra("config")

        if (action == ACTION_STOP) {
            android.util.Log.d("NativeVpnLifecycle", "onStartCommand: ACTION_STOP received, executing immediate forceStop")
            forceStopVpnNowInternal()
            return START_NOT_STICKY
        }

        if (action == ACTION_DISCONNECT) {
            android.util.Log.d("NativeVpnLifecycle", "onStartCommand: ACTION_DISCONNECT received")
            MainActivity.sendVpnStatus("USER_ACTION:DISCONNECT")
            forceStopVpnNowInternal()
            return START_NOT_STICKY
        }

        if (action == ACTION_SKIP_SERVER) {
            android.util.Log.d("NativeVpnLifecycle", "onStartCommand: ACTION_SKIP_SERVER received, notifying Dart to skip")
            MainActivity.sendVpnStatus("USER_ACTION:SKIP")
            return START_NOT_STICKY
        }

        if (action == ACTION_START) {
            try {
                startServiceForeground()
            } catch (e: Throwable) {
                android.util.Log.e("NativeVpnLifecycle", "Error starting foreground synchronously: ${e.message}")
            }
        }

        serviceScope.launch {
            if (action == ACTION_START && config != null) {
                startVpn(config)
            }
        }

        return START_NOT_STICKY
    }

    private fun startServiceForeground() {
        createNotificationChannel()
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                VPN_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(VPN_NOTIFICATION_ID, notification)
        }
    }

    private suspend fun startVpn(rawInput: String) {
        nativeCallMutex.withLock {
            // Seamless Server Switching: Stop previous core if switching servers while VPN is already active
            if (isVpnRunning) {
                android.util.Log.i("NativeVpnLifecycle", "VPN already running, reloading core with new server...")
                val oldServer = mainServer
                mainServer = null
                if (oldServer != null) {
                    try {
                        try {
                            oldServer.javaClass.getMethod("serviceStop").invoke(oldServer)
                        } catch (_: Throwable) {
                            oldServer.closeService()
                        }
                    } catch (_: Throwable) {}
                    try { oldServer.close() } catch (_: Throwable) {}
                }
                isVpnRunning = false
            }

            isVpnRunning = true

            try {
                startServiceForeground()
            } catch (ignored: Throwable) {}

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

                if (vpnInterface == null) {
                    val builder = Builder()
                    builder.setSession("iVPN Connection")
                    builder.addAddress("172.19.0.1", 28)
                    builder.addRoute("0.0.0.0", 0)
                    builder.setMtu(1500)
                    builder.addDnsServer("8.8.8.8")
                    builder.addDnsServer("1.1.1.1")

                    // CRITICAL FIX: Exclude own package so sing-box outbound sockets and app traffic
                    // NEVER route into tun0 (stops infinite routing loop and runaway 433MB upload traffic)
                    try {
                        builder.addDisallowedApplication(packageName)
                        android.util.Log.i("NativeVpnLifecycle", "Successfully excluded $packageName from VPN tunnel")
                    } catch (e: Throwable) {
                        android.util.Log.e("NativeVpnLifecycle", "Failed to exclude $packageName: ${e.message}")
                    }

                    // Add IPv6 route to prevent IPv6 traffic/DNS leaks from bypassing VPN
                    try {
                        builder.addAddress("fdfe:dcba:9876::1", 126)
                        builder.addRoute("::", 0)
                    } catch (e: Throwable) {
                        android.util.Log.w("NativeVpnLifecycle", "IPv6 routing setup warning: ${e.message}")
                    }

                    vpnInterface = builder.establish()
                }

                if (vpnInterface == null) {
                    stopVpnInternal()
                    return
                }

                // SAFE CALL - pass JSON content string directly without invalid file_descriptor injection
                try {
                    ensureLibboxSetup(cacheDir)
                    mainServer = Libbox.newCommandServer(StubCommandServerHandler(), this@SingboxVpnService)
                    mainServer?.startOrReloadService(configJson, OverrideOptions())
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
                MainActivity.sendVpnStatus("ERROR")
                stopVpnInternal()
            }
        }
    }

    private suspend fun stopVpn() {
        forceStopVpnNowInternal()
    }

    private fun stopVpnInternal() {
        forceStopVpnNowInternal()
    }

    fun forceStopVpnNowInternal() {
        android.util.Log.d("NativeVpnLifecycle", "forceStopVpnNowInternal invoked")
        isVpnRunning = false

        // 1. Close vpnInterface FIRST so OS immediately destroys tun0
        try {
            vpnInterface?.close()
        } catch (_: Throwable) {
        } finally {
            vpnInterface = null
        }

        // 2. Stop and close mainServer
        val server = mainServer
        mainServer = null
        if (server != null) {
            try {
                try {
                    server.javaClass.getMethod("serviceStop").invoke(server)
                } catch (_: Throwable) {
                    server.closeService()
                }
            } catch (_: Throwable) {}
            try {
                server.close()
            } catch (_: Throwable) {}
        }

        // 3. Remove foreground notification
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.cancel(LOW_TIME_NOTIFICATION_ID)
        } catch (e: Throwable) {
            android.util.Log.e("NativeVpnLifecycle", "Error in stopForeground: ${e.message}")
        }

        // 4. Notify Dart side BEFORE stopSelf()
        MainActivity.sendVpnStatus("DISCONNECTED")

        // 5. Stop service
        try {
            stopSelf()
        } catch (e: Throwable) {
            android.util.Log.e("NativeVpnLifecycle", "Error in stopSelf: ${e.message}")
        }

        android.util.Log.d("NativeVpnLifecycle", "forceStopVpnNowInternal completed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel =
                NotificationChannel(
                    VPN_NOTIFICATION_CHANNEL_ID,
                    "iVPN Connection Status",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }

            val lowTimeChannel =
                NotificationChannel(
                    LOW_TIME_CHANNEL_ID,
                    "iVPN Account Alerts",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Alerts when VPN access time is running out"
                }

            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
            manager?.createNotificationChannel(lowTimeChannel)
        }
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val kb = bytes / 1024.0
        if (kb < 1024) return String.format("%.1f KB", kb)
        val mb = kb / 1024.0
        if (mb < 1024) return String.format("%.1f MB", mb)
        val gb = mb / 1024.0
        return String.format("%.2f GB", gb)
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

        val skipIntent = Intent(this, SingboxVpnService::class.java).apply {
            putExtra("action", ACTION_SKIP_SERVER)
        }
        val skipPendingIntent = PendingIntent.getService(
            this,
            1,
            skipIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val disconnectIntent = Intent(this, SingboxVpnService::class.java).apply {
            putExtra("action", ACTION_DISCONNECT)
        }
        val disconnectPendingIntent = PendingIntent.getService(
            this,
            2,
            disconnectIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val title = if (currentServerName.isNotBlank() && currentServerName != "Connected") {
            "$currentServerName • Connected"
        } else {
            "iVPN Connected"
        }

        val content = buildString {
            if (currentRemainingTimeText.isNotBlank()) {
                append("⏳ $currentRemainingTimeText  •  ")
            }
            append("↓ ${formatBytes(lastDownSpeed)}/s   ↑ ${formatBytes(lastUpSpeed)}/s  •  Total: ${formatBytes(lastRx + lastTx)}")
        }

        return NotificationCompat
            .Builder(this, VPN_NOTIFICATION_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_media_next, "Skip Server", skipPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", disconnectPendingIntent)
            .build()
    }

    fun updateNotificationStats() {
        if (!isVpnRunning) return
        val notification = createNotification()
        val manager = getSystemService(NotificationManager::class.java)
        manager?.notify(VPN_NOTIFICATION_ID, notification)
    }

    fun checkLowTimeAlert(remainingSeconds: Int) {
        if (!isVpnRunning) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (remainingSeconds in 1..300) { // Under 5 minutes left
            val intent = Intent(this, MainActivity::class.java).apply {
                putExtra("action", "open_reward_ad")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pi = PendingIntent.getActivity(
                this,
                3,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val minutesLeft = Math.max(1, remainingSeconds / 60)
            val alert = NotificationCompat.Builder(this, LOW_TIME_CHANNEL_ID)
                .setContentTitle("Access Time Running Low")
                .setContentText("You have $minutesLeft min left. Tap to extend time now.")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
            manager.notify(LOW_TIME_NOTIFICATION_ID, alert)
        } else if (remainingSeconds > 300 || remainingSeconds <= 0) {
            manager.cancel(LOW_TIME_NOTIFICATION_ID)
        }
    }

    override fun openTun(options: TunOptions): Int {
        val fd = vpnInterface?.fd ?: -1
        android.util.Log.d("NativeVpnLifecycle", "openTun called by libbox: returning fd $fd")
        return fd
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        val ok = protect(fd)
        android.util.Log.d("NativeVpnLifecycle", "autoDetectInterfaceControl: protect($fd) -> $ok")
    }

    override fun onRevoke() {
        super.onRevoke()
        android.util.Log.d("NativeVpnLifecycle", "onRevoke called by OS")
        MainActivity.sendVpnStatus("ERROR: REVOKED")
        forceStopVpnNowInternal()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        android.util.Log.d("NativeVpnLifecycle", "onTaskRemoved called - cleaning up VPN")
        forceStopVpnNowInternal()
    }

    override fun onDestroy() {
        super.onDestroy()
        android.util.Log.d("NativeVpnLifecycle", "onDestroy called")
        if (activeServiceInstance === this) {
            activeServiceInstance = null
        }
        forceStopVpnNowInternal()
        try {
            runBlocking {
                nativeCallMutex.withLock {
                    closeTestServerUnlocked()
                }
            }
        } catch (e: Throwable) {
            android.util.Log.e("NativeVpnLifecycle", "Error closing testServer in onDestroy: ${e.message}")
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
        if (!message.isNullOrBlank()) {
            android.util.Log.i("SingboxCore", "[LOG] $message")
        }
        MainActivity.sendVpnStatus(message ?: "")
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener?) { }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String?,
        sourcePort: Int,
        destinationAddress: String?,
        destinationPort: Int,
    ): io.nekohasekai.libbox.ConnectionOwner? {
        throw Exception("Connection owner not found")
    }

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

    override fun serviceReload() {
        android.util.Log.i("SingboxCore", "Core serviceReload called")
    }

    override fun serviceStop() {
        android.util.Log.i("SingboxCore", "Core serviceStop called")
    }

    override fun setSystemProxyEnabled(enabled: Boolean) {
        android.util.Log.i("SingboxCore", "Core setSystemProxyEnabled: $enabled")
    }

    override fun writeDebugMessage(message: String?) {
        if (!message.isNullOrBlank()) {
            android.util.Log.i("SingboxCore", message)
        }
    }
}
