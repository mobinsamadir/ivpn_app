import sys

with open('lib/services/native_vpn_service.dart', 'r') as f:
    content = f.read()

search = """      Timer(const Duration(seconds: 15), () {
        if (_lastStatus != "CONNECTED" && !_lastStatus.startsWith("ERROR")) {
          AdvancedLogger.warn(
            "Native layer timed out. Injecting synthetic ERROR event.",
          );
          _statusController.add("ERROR: NATIVE_TIMEOUT");
        }
      });"""

replace = """      Timer(const Duration(seconds: 15), () {
        AdvancedLogger.warn("Native layer timed out. Injecting synthetic ERROR event.");
        _statusController.add("ERROR: NATIVE_TIMEOUT");
      });"""

if search in content:
    content = content.replace(search, replace)
    with open('lib/services/native_vpn_service.dart', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
