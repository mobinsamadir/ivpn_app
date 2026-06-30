import sys

with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'r') as f:
    content = f.read()

search = """                val testConfigFile = File(tempDir, "test_${System.currentTimeMillis()}.json")
                testConfigFile.writeText(json.toString())

                // SAFE CALL - pass JSON content string
                val testServer = try {
                    val options = io.nekohasekai.libbox.SetupOptions()
                    options.setBasePath(tempDir.absolutePath)
                    options.setWorkingPath(tempDir.absolutePath)
                    options.setTempPath(tempDir.absolutePath)
                    Libbox.setup(options)
                    Libbox.newCommandServer(StubCommandServerHandler(), StubPlatformInterface())
                } catch (e: Exception) {
                    e.printStackTrace()
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                    return@withContext
                }

                try {
                    testServer.startOrReloadService(json.toString(), null)
                } catch (e: Exception) {
                    e.printStackTrace()
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                    return@withContext
                }"""

replace = """                val testConfigFile = File(tempDir, "test_${System.currentTimeMillis()}.json")
                testConfigFile.writeText(json.toString())

                closeTestServer()

                // SAFE CALL - pass JSON content string
                testServer = try {
                    val options = io.nekohasekai.libbox.SetupOptions()
                    options.setBasePath(tempDir.absolutePath)
                    options.setWorkingPath(tempDir.absolutePath)
                    options.setTempPath(tempDir.absolutePath)
                    Libbox.setup(options)
                    Libbox.newCommandServer(StubCommandServerHandler(), StubPlatformInterface())
                } catch (e: Exception) {
                    e.printStackTrace()
                    result?.let { r -> Handler(Looper.getMainLooper()).post { r.success(-1) } }
                    isTestRunning.set(false)
                    return@withContext
                }

                try {
                    testServer?.startOrReloadService(json.toString(), null)
                } catch (e: Exception) {
                    e.printStackTrace()
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
