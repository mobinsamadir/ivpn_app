package com.example.ivpnnew

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

class SafeResult(
    private val result: MethodChannel.Result,
) : MethodChannel.Result {
    private val isReplied = AtomicBoolean(false)

    override fun success(res: Any?) {
        if (isReplied.compareAndSet(false, true)) {
            Handler(Looper.getMainLooper()).post {
                result.success(res)
            }
        }
    }

    override fun error(
        errorCode: String,
        errorMessage: String?,
        errorDetails: Any?,
    ) {
        if (isReplied.compareAndSet(false, true)) {
            Handler(Looper.getMainLooper()).post {
                result.error(errorCode, errorMessage, errorDetails)
            }
        }
    }

    override fun notImplemented() {
        if (isReplied.compareAndSet(false, true)) {
            Handler(Looper.getMainLooper()).post {
                result.notImplemented()
            }
        }
    }
}

class MainActivity : FlutterActivity() {
    private val channel = "com.example.ivpn/vpn"
    private val eventChannel = "com.example.ivpn/vpn_status"
    private val vpnRequestCode = 0x0F
    private var pendingConfig: String? = null
    private var pendingVpnResult: MethodChannel.Result? = null

    // Scope for launching coroutines on the Main thread
    private val scope = CoroutineScope(Dispatchers.Main)

    companion object {
        var eventSink: EventChannel.EventSink? = null

        fun sendVpnStatus(status: String) {
            Handler(Looper.getMainLooper()).post {
                eventSink?.success(status)
            }
        }
    }

    override fun configureFlutterEngine(
        @NonNull flutterEngine: FlutterEngine,
    ) {
        super.configureFlutterEngine(flutterEngine)

        // Setup EventChannel for VPN Status Updates
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    eventSink = events
                    // Send current state if known (optional, but good practice)
                    if (SingboxVpnService.isVpnRunning) {
                        events?.success("CONNECTED")
                    } else {
                        events?.success("DISCONNECTED")
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, rawResult ->
            val result = SafeResult(rawResult)
            scope.launch(Dispatchers.IO) {
                try {
                    when (call.method) {
                        "startVpn" -> {
                            val config = call.argument<String>("config")
                            withContext(Dispatchers.Main) {
                                if (config != null && config.isNotBlank()) {
                                    pendingConfig = config
                                    pendingVpnResult = result
                                    prepareVpn()
                                } else {
                                    result.error("INVALID_CONFIG", "Config string is null or empty", null)
                                }
                            }
                        }
                        "stopVpn" -> {
                            withContext(Dispatchers.Main) {
                                stopVpnService()
                                result.success(null)
                            }
                        }
                        "testConfig" -> {
                            val config = call.argument<String>("config")
                            withContext(Dispatchers.Main) {
                                if (android.net.VpnService.prepare(this@MainActivity) != null) {
                                    result.error("PERMISSION_DENIED", "VPN Permission not granted yet", null)
                                    return@withContext
                                }
                            }
                            if (config != null && config.isNotBlank()) {
                                SingboxVpnService.measurePing(config, cacheDir, result)
                            } else {
                                result.error("INVALID_CONFIG", "Config string is null or empty", null)
                            }
                        }
                        "startTestProxy" -> {
                            val config = call.argument<String>("config")
                            withContext(Dispatchers.Main) {
                                if (android.net.VpnService.prepare(this@MainActivity) != null) {
                                    result.error("PERMISSION_DENIED", "VPN Permission not granted yet", null)
                                    return@withContext
                                }
                            }
                            if (config != null && config.isNotBlank()) {
                                SingboxVpnService.startTestProxy(config, cacheDir, result)
                            } else {
                                result.error("INVALID_CONFIG", "Config string is null or empty", null)
                            }
                        }
                        "stopTestProxy" -> {
                            SingboxVpnService.stopTestProxy()
                            result.success(null)
                        }
                        else -> {
                            result.notImplemented()
                        }
                    }
                } catch (e: Throwable) {
                    result.error("METHOD_ERROR", "Exception during method call: ${e.message}", null)
                }
            }
        }
    }

    private fun prepareVpn() {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            startActivityForResult(intent, vpnRequestCode)
        } else {
            // Already granted
            if (pendingConfig != null) {
                val serviceIntent =
                    Intent(this, SingboxVpnService::class.java).apply {
                        putExtra("action", SingboxVpnService.ACTION_START)
                        putExtra("config", pendingConfig)
                    }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                pendingVpnResult?.success(null)
                pendingConfig = null
                pendingVpnResult = null
            }
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnRequestCode) {
            if (resultCode == Activity.RESULT_OK && pendingConfig != null) {
                val serviceIntent =
                    Intent(this, SingboxVpnService::class.java).apply {
                        putExtra("action", SingboxVpnService.ACTION_START)
                        putExtra("config", pendingConfig)
                    }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                pendingVpnResult?.success(null)
            } else {
                val details = mapOf("permanentlyDenied" to false)
                pendingVpnResult?.error("VPN_PERMISSION_DENIED", "VPN permission was denied by the user.", details)
            }
            pendingConfig = null
            pendingVpnResult = null
        }
    }

    private fun stopVpnService() {
        val serviceIntent =
            Intent(this, SingboxVpnService::class.java).apply {
                putExtra("action", SingboxVpnService.ACTION_STOP)
            }
        startService(serviceIntent)
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
}
