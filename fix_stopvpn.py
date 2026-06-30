import sys

with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'r') as f:
    content = f.read()

search = """    private fun stopVpn() {
        if (!isVpnRunning.get()) return
        isVpnRunning.set(false)

        try {
            mainServer?.close()
            mainServer = null
            vpnInterface?.close()
            vpnInterface = null
            stopForeground(true)
            stopSelf()

            // CRITICAL FIX: Broadcast "DISCONNECTED" State to Dart
            MainActivity.sendVpnStatus("DISCONNECTED")

        } catch (e: Exception) {
            e.printStackTrace()
        }
    }"""

replace = """    private fun stopVpn() {
        if (!isVpnRunning.get()) return
        isVpnRunning.set(false)
        android.util.Log.d("NativeVpnLifecycle", "stopVpn called")

        try {
            mainServer?.close()
            mainServer = null
            vpnInterface?.close()
            vpnInterface = null
            stopForeground(true)
            stopSelf()

            // CRITICAL FIX: Broadcast "DISCONNECTED" State to Dart
            MainActivity.sendVpnStatus("DISCONNECTED")
            android.util.Log.d("NativeVpnLifecycle", "stopVpn completed successfully")
        } catch (e: Exception) {
            android.util.Log.e("NativeVpnLifecycle", "stopVpn error: ${e.message}")
            e.printStackTrace()
        }
    }"""

if search in content:
    content = content.replace(search, replace)
    with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
