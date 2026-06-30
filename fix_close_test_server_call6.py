import sys

with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'r') as f:
    content = f.read()

search = """                try {
                    val options = io.nekohasekai.libbox.SetupOptions()
                    options.setBasePath(configDir.absolutePath)
                    options.setWorkingPath(configDir.absolutePath)
                    options.setTempPath(configDir.absolutePath)
                    Libbox.setup(options)
                    mainServer = Libbox.newCommandServer(StubCommandServerHandler(), this@SingboxVpnService)
                    mainServer?.startOrReloadService(jsonObject.toString(), null)
                } catch (e: Exception) {
                    e.printStackTrace()
                    MainActivity.sendVpnStatus("ERROR: START_FAILED - ${e.message}")
                    stopVpn()
                    return@launch
                }"""

replace = """                try {
                    val options = io.nekohasekai.libbox.SetupOptions()
                    options.setBasePath(configDir.absolutePath)
                    options.setWorkingPath(configDir.absolutePath)
                    options.setTempPath(configDir.absolutePath)
                    Libbox.setup(options)
                    mainServer = Libbox.newCommandServer(StubCommandServerHandler(), this@SingboxVpnService)
                    mainServer?.startOrReloadService(jsonObject.toString(), null)
                } catch (e: Exception) {
                    e.printStackTrace()
                    android.util.Log.e("NativeVpnLifecycle", "StartOrReloadService Error: ${e.message}")
                    MainActivity.sendVpnStatus("ERROR: START_FAILED - ${e.message}")
                    stopVpn()
                    return@launch
                }"""

if search in content:
    content = content.replace(search, replace)
    with open('android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
