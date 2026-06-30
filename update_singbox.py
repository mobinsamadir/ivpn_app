import sys

with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'r') as f:
    content = f.read()

search = """        val isVpnRunning = AtomicBoolean(false)
        private val isTestRunning = AtomicBoolean(false)
        private val testMutex = Mutex()

        private fun getValidJsonConfig(input: String): String {"""

replace = """        val isVpnRunning = AtomicBoolean(false)
        private val isTestRunning = AtomicBoolean(false)
        private val testMutex = Mutex()
        private var testServer: io.nekohasekai.libbox.CommandServer? = null

        private suspend fun closeTestServer() {
            testMutex.withLock {
                if (testServer != null) {
                    try {
                        android.util.Log.d("NativeVpnLifecycle", "Closing existing testServer...")
                        testServer?.close()
                        testServer = null
                        android.util.Log.d("NativeVpnLifecycle", "testServer successfully closed.")
                    } catch (e: Exception) {
                        android.util.Log.e("NativeVpnLifecycle", "Error closing testServer: ${e.message}")
                        e.printStackTrace()
                    }
                }
            }
        }

        private fun getValidJsonConfig(input: String): String {"""

if search in content:
    content = content.replace(search, replace)
    with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
