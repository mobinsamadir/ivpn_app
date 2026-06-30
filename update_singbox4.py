import sys

with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'r') as f:
    content = f.read()

search = """    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
        serviceScope.cancel()
    }"""

replace = """    override fun onDestroy() {
        super.onDestroy()
        android.util.Log.d("NativeVpnLifecycle", "onDestroy called")
        stopVpn()
        serviceScope.launch {
            closeTestServer()
            serviceScope.cancel()
        }
    }"""

if search in content:
    content = content.replace(search, replace)
    with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
