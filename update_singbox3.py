import sys

with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'r') as f:
    content = f.read()

search = """        suspend fun stopTestProxy() = withContext(Dispatchers.IO) {
            if (isTestRunning.get()) {
                try {
                    // stop test proxy
                } catch (e: Exception) {
                    e.printStackTrace()
                } finally {
                    isTestRunning.set(false)
                }
            }
        }"""

replace = """        suspend fun stopTestProxy() = withContext(Dispatchers.IO) {
            if (isTestRunning.get()) {
                try {
                    closeTestServer()
                } catch (e: Exception) {
                    e.printStackTrace()
                } finally {
                    isTestRunning.set(false)
                }
            }
        }"""

if search in content:
    content = content.replace(search, replace)
    with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
