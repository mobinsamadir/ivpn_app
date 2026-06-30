import sys

with open('lib/services/native_vpn_service.dart', 'r') as f:
    content = f.read()

search = """      // Start a fallback timer just in case the OS never sends CONNECTED or ERROR
      // We will explicitly push an ERROR event if we don't hear back within 15 seconds.
      Timer(const Duration(seconds: 15), () {
        // Fire a synthetic event into the stream controller if it's still hanging
        // This is safe because _eventController is a broadcast stream and we just want to unblock listeners
        // Let ConfigManager handle the timeout specifically. But we can help by throwing if it hangs.
      });"""

replace = """      // We will explicitly push an ERROR event if we don't hear back within 15 seconds.
      Timer(const Duration(seconds: 15), () {
        if (_lastStatus != "CONNECTED" && !_lastStatus.startsWith("ERROR")) {
            AdvancedLogger.warn("Native layer timed out. Injecting synthetic ERROR event.");
            _statusController.add("ERROR: NATIVE_TIMEOUT");
        }
      });"""

if search in content:
    content = content.replace(search, replace)
    with open('lib/services/native_vpn_service.dart', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
