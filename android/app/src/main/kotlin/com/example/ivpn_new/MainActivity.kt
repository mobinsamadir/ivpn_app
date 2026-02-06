package com.example.ivpn_new

import android.content.Intent
import android.os.Build
import android.os.PowerManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.ivpn_new/method"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register the method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val config = call.argument<String>("config")
                    startVpnService(config)
                    result.success(null)
                }
                "disconnect" -> {
                    stopVpnService()
                    result.success(null)
                }
                "test_config" -> {
                    // For now, just return a success response
                    // In a real implementation, this would test the config
                    result.success(100) // Return a sample ping value
                }
                else -> result.notImplemented()
            }
        }

        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }

    private fun startVpnService(config: String?) {
        // Request VPN permission if not already granted
        val vpnIntent = Intent(this, MyVpnService::class.java).apply {
            putExtra("action", "start")
            putExtra("config", config)
        }

        // Start the VPN service
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(vpnIntent)
        } else {
            startService(vpnIntent)
        }
    }

    private fun stopVpnService() {
        val vpnIntent = Intent(this, MyVpnService::class.java).apply {
            putExtra("action", "stop")
        }
        startService(vpnIntent)
    }
}
