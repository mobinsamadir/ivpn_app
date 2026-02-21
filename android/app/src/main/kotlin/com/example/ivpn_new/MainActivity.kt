package com.example.ivpn_new

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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.ivpn/vpn"
    private val EVENT_CHANNEL = "com.example.ivpn/vpn_status"
    private val VPN_REQUEST_CODE = 0x0F
    private var pendingConfig: String? = null

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

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup EventChannel for VPN Status Updates
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    // Send current state if known (optional, but good practice)
                    if (SingboxVpnService.isVpnRunning.get()) {
                         events?.success("CONNECTED")
                    } else {
                         events?.success("DISCONNECTED")
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val config = call.argument<String>("config")
                    if (config != null) {
                        pendingConfig = config
                        prepareVpn()
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Config is null", null)
                    }
                }
                "stopVpn" -> {
                    stopVpnService()
                    result.success(null)
                }
                "testConfig" -> {
                    val config = call.argument<String>("config")
                    if (config != null) {
                        // Launch in IO scope properly via a wrapper or direct call
                        // Since measurePing is suspend, we need a scope.
                        // However, setMethodCallHandler runs on Main thread.
                        // We use the activity scope or create a quick one.
                        CoroutineScope(Dispatchers.IO).launch {
                            val ping = SingboxVpnService.measurePing(config, cacheDir)
                            // Post result back to Main thread
                            Handler(Looper.getMainLooper()).post {
                                result.success(ping)
                            }
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Config is null", null)
                    }
                }
                "startTestProxy" -> {
                    val config = call.argument<String>("config")
                    if (config != null) {
                         CoroutineScope(Dispatchers.IO).launch {
                             val port = SingboxVpnService.startTestProxy(config, cacheDir)
                             Handler(Looper.getMainLooper()).post {
                                 result.success(port)
                             }
                         }
                    } else {
                        result.error("INVALID_ARGUMENT", "Config is null", null)
                    }
                }
                "stopTestProxy" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        SingboxVpnService.stopTestProxy()
                        Handler(Looper.getMainLooper()).post {
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun prepareVpn() {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            onActivityResult(VPN_REQUEST_CODE, Activity.RESULT_OK, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && pendingConfig != null) {
                val serviceIntent = Intent(this, SingboxVpnService::class.java).apply {
                    putExtra("action", SingboxVpnService.ACTION_START)
                    putExtra("config", pendingConfig)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
            }
            pendingConfig = null
        }
    }

    private fun stopVpnService() {
        val serviceIntent = Intent(this, SingboxVpnService::class.java).apply {
            putExtra("action", SingboxVpnService.ACTION_STOP)
        }
        startService(serviceIntent)
    }
}
