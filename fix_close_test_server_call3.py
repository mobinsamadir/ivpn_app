import sys

with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'r') as f:
    content = f.read()

search = """                try {
                    newTestServer?.startOrReloadService(json.toString(), null)
                    testMutex.withLock {
                        testServer = newTestServer
                    }
                } catch (e: Exception) {"""

replace = """                try {
                    newTestServer?.startOrReloadService(json.toString(), null)
                    testMutex.withLock {
                        testServer = newTestServer
                    }
                } catch (e: Exception) {
                    newTestServer?.close()"""

if search in content:
    content = content.replace(search, replace)
    with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
