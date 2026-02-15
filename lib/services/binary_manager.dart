import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'windows_vpn_service.dart';
import '../utils/advanced_logger.dart';

class BinaryManager {
  /// Ensures the Sing-box binary is available and executable.
  /// Returns the absolute path to the executable.
  static Future<String> ensureBinary() async {
    if (Platform.isWindows) {
      return await WindowsVpnService.getExecutablePath();
    } else if (Platform.isAndroid) {
      return await _ensureAndroidBinary();
    } else {
      // Fallback for Linux/MacOS (assume installed in PATH or relative)
      return "sing-box";
    }
  }

  /// Android-specific logic to copy binary from assets to internal storage and make it executable.
  static Future<String> _ensureAndroidBinary() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final binaryPath = p.join(appDir.path, 'libsingbox.so');
      final binaryFile = File(binaryPath);

      // Check if binary exists
      if (!await binaryFile.exists()) {
        AdvancedLogger.info("BinaryManager: Android binary not found at $binaryPath. Copying from assets...");

        try {
          // Copy from assets
          final byteData = await rootBundle.load('assets/executables/android/libsingbox.so');
          final buffer = byteData.buffer;
          await binaryFile.writeAsBytes(
            buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
            flush: true,
          );
          AdvancedLogger.info("BinaryManager: Binary copied successfully.");
        } catch (e) {
          AdvancedLogger.error("BinaryManager: Failed to copy binary from assets: $e");
          // Fallback: Check if it's in the native library path (e.g. split APKs)
          // For now, rethrow to trigger fail-safe in caller or let it fail hard if asset is missing.
          // But wait, the user said "Assume that I ... will manually place ...".
          // If load fails, it means the asset isn't there.
          throw Exception("Failed to load Android binary from assets: $e");
        }
      }

      // Ensure executable permissions (chmod +x)
      // Note: On some Android versions, files in app support dir might not need chmod if written by app,
      // but it's safer to try.
      try {
        final result = await Process.run('chmod', ['+x', binaryPath]);
        if (result.exitCode != 0) {
           AdvancedLogger.warn("BinaryManager: chmod +x failed: ${result.stderr}");
        } else {
           AdvancedLogger.info("BinaryManager: chmod +x executed successfully.");
        }
      } catch (e) {
        AdvancedLogger.warn("BinaryManager: Failed to run chmod: $e");
      }

      return binaryPath;
    } catch (e) {
      AdvancedLogger.error("BinaryManager: Critical error ensuring Android binary: $e");
      rethrow;
    }
  }
}
