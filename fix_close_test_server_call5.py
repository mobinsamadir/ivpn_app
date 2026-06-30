import sys

with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'r') as f:
    content = f.read()

search = """                try {
                    newTestServer?.startOrReloadService(json.toString(), null)
                    testMutex.withLock {
                        testServer = newTestServer
                    }
                } catch (e: Exception) {
                    newTestServer?.close()
                    e.printStackTrace()
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                    isTestRunning.set(false)
                    return@withContext
                }"""

replace = """                try {
                    newTestServer?.startOrReloadService(json.toString(), null)
                    testMutex.withLock {
                        testServer = newTestServer
                    }
                } catch (e: Exception) {
                    newTestServer?.close()
                    e.printStackTrace()
                    MainActivity.sendVpnStatus("ERROR: TEST_START_FAILED - ${e.message}")
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                    isTestRunning.set(false)
                    return@withContext
                }"""

if search in content:
    content = content.replace(search, replace)
    with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
