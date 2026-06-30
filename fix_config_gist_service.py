import sys
import json

with open('lib/services/config_gist_service.dart', 'r') as f:
    content = f.read()

search = """      // Fail-safe
      final backupJson = prefs.getString(_backupConfigsKey);
      if (backupJson != null && backupJson.isNotEmpty) {
        try {
          final List<dynamic> rawList = jsonDecode(backupJson);
          final List<String> backupConfigs =
              rawList.map((e) => e.toString()).toList();

          if (backupConfigs.isNotEmpty) {
            AdvancedLogger.warn(
              "⚠️ Network failure. Using last known good configuration.",
            );
            final added = await manager.addConfigs(
              backupConfigs,
              checkBlacklist: true,
            );"""

replace = """      // Fail-safe
      final backupJson = prefs.getString(_backupConfigsKey);
      if (backupJson != null && backupJson.isNotEmpty) {
        try {
          final List<dynamic> rawList = jsonDecode(backupJson);
          final List<String> backupConfigs =
              rawList.map((e) => e.toString()).where((c) {
                if (c.trim().isEmpty) return false;
                if (!c.trim().startsWith('{')) {
                  // If it doesn't start with {, it's likely a raw URL, which addConfigs handles
                  // If it's supposed to be JSON, this would be an issue. But addConfigs parses URLs.
                  return true;
                }
                try {
                  jsonDecode(c);
                  return true;
                } catch (_) {
                  return false;
                }
              }).toList();

          if (backupConfigs.isNotEmpty) {
            AdvancedLogger.warn(
              "⚠️ Network failure. Using last known good configuration.",
            );
            final added = await manager.addConfigs(
              backupConfigs,
              checkBlacklist: true,
            );"""

if search in content:
    content = content.replace(search, replace)
    with open('lib/services/config_gist_service.dart', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
