package com.ivpn_new

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
    private var pendingTestProxyResult: MethodChannel.Result? = null
    private var pendingMeasurePingResult: MethodChannel.Result? = null
    private var pendingAction: String? = null

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
                                                "hasVpnPermission" -> {
                            withContext(Dispatchers.Main) {
                                val intent = VpnService.prepare(this@MainActivity)
                                result.success(intent == null) // If null, permission is already granted
                            }
                        }
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
                                val intent = android.net.VpnService.prepare(this@MainActivity)
                                if (intent != null) {
                                    pendingConfig = config
                                    pendingMeasurePingResult = result
                                    pendingAction = "testConfig"
                                    startActivityForResult(intent, vpnRequestCode)
                                } else {
                                    if (config != null && config.isNotBlank()) {
                                        SingboxVpnService.measurePing(config, cacheDir, result)
                                    } else {
                                        result.error("INVALID_CONFIG", "Config string is null or empty", null)
                                    }
                                }
                            }
                        }
                        "startTestProxy" -> {
                            android.util.Log.i("MainActivity", "startTestProxy invoked")
                            val config = call.argument<String>("config")
                            withContext(Dispatchers.Main) {
                                val intent = android.net.VpnService.prepare(this@MainActivity)
                                if (intent != null) {
                                    android.util.Log.w("MainActivity", "startTestProxy: Permission needed, launching intent")
                                    pendingConfig = config
                                    pendingTestProxyResult = result
                                    pendingAction = "startTestProxy"
                                    startActivityForResult(intent, vpnRequestCode)
                                } else {
                                    if (config != null && config.isNotBlank()) {
                                        try {
                                            SingboxVpnService.startTestProxy(config, cacheDir, result)
                                        } catch (e: Exception) {
                                            android.util.Log.e("MainActivity", "Native crash in startTestProxy: ${e.message}", e)
                                            result.error("NATIVE_CRASH", "Native crash in startTestProxy: ${e.message}", null)
                                        }
                                    } else {
                                        android.util.Log.e("MainActivity", "startTestProxy failed: INVALID_CONFIG")
                                        result.error("INVALID_CONFIG", "Config string is null or empty", null)
                                    }
                                }
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
                when (pendingAction) {
                    "testConfig" -> {
                            val config = call.argument<String>("config")
                            withContext(Dispatchers.Main) {
                                val intent = android.net.VpnService.prepare(this@MainActivity)
                                if (intent != null) {
                                    pendingConfig = config
                                    pendingMeasurePingResult = result
                                    pendingAction = "testConfig"
                                    startActivityForResult(intent, vpnRequestCode)
                                } else {
                                    if (config != null && config.isNotBlank()) {
                                        SingboxVpnService.measurePing(config, cacheDir, result)
                                    } else {
                                        result.error("INVALID_CONFIG", "Config string is null or empty", null)
                                    }
                                }
                            }
                        }
                        "startTestProxy" -> {
                        try {
                            SingboxVpnService.startTestProxy(pendingConfig!!, cacheDir, pendingTestProxyResult)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Native crash in startTestProxy: ${e.message}", e)
                            pendingTestProxyResult?.error("NATIVE_CRASH", "Native crash in startTestProxy: ${e.message}", null)
                        }
                        pendingTestProxyResult = null
                    }
                    else -> {
                        // Default startVpn behavior
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
                    }
                }
            } else {
                val details = mapOf("permanentlyDenied" to false)
                when (pendingAction) {
                    "testConfig" -> pendingMeasurePingResult?.error("VPN_PERMISSION_DENIED", "VPN permission was denied by the user.", details)
                    "startTestProxy" -> pendingTestProxyResult?.error("VPN_PERMISSION_DENIED", "VPN permission was denied by the user.", details)
                    else -> pendingVpnResult?.error("VPN_PERMISSION_DENIED", "VPN permission was denied by the user.", details)
                }
                pendingMeasurePingResult = null
                pendingTestProxyResult = null
                pendingVpnResult = null
            }
            pendingConfig = null
            pendingAction = null
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
