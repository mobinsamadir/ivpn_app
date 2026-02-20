package com.example.ivpn_new

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.ivpn/vpn"
    private val VPN_REQUEST_CODE = 0x0F
    private var pendingConfig: String? = null

    // Scope for launching coroutines on the Main thread
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                    // LEGACY: Keep for compatibility if needed, but EphemeralTester prefers startTestProxy
                    val config = call.argument<String>("config")
                    if (config != null) {
                        scope.launch {
                            val ping = SingboxVpnService.measurePing(config, cacheDir)
                            result.success(ping)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Config is null", null)
                    }
                }
                // --- NEW METHODS ---
                "startTestProxy" -> {
                    val config = call.argument<String>("config")
                    if (config != null) {
                         scope.launch {
                             // Returns port (>0) or error code (<0)
                             val port = SingboxVpnService.startTestProxy(config, cacheDir)
                             result.success(port)
                         }
                    } else {
                        result.error("INVALID_ARGUMENT", "Config is null", null)
                    }
                }
                "stopTestProxy" -> {
                    scope.launch {
                        SingboxVpnService.stopTestProxy()
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        GeneratedPluginRegistrant.registerWith(flutterEngine)
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
            } else {
                // Permission denied or config missing
            }
            pendingConfig = null
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun stopVpnService() {
        val serviceIntent = Intent(this, SingboxVpnService::class.java).apply {
            putExtra("action", SingboxVpnService.ACTION_STOP)
        }
        startService(serviceIntent)
    }
}
