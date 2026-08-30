import 'dart:io';
import 'package:flutter/foundation.dart';
import 'windows_vpn_service.dart';

class BinaryManager {
  @visibleForTesting
  static bool? debugIsWindows;

  @visibleForTesting
  static bool? debugIsAndroid;

  /// Ensures the Sing-box binary is available and executable.
  /// Returns the absolute path to the executable.
  static Future<String> ensureBinary() async {
    final isWindows = debugIsWindows ?? Platform.isWindows;
    final isAndroid = debugIsAndroid ?? Platform.isAndroid;

    if (isWindows) {
      return await WindowsVpnService.getExecutablePath();
    } else if (isAndroid) {
      // On Android, we now use JNI (libbox.aar) via NativeVpnService.
      // The standalone binary is no longer bundled to save space.
      throw UnsupportedError(
        "BinaryManager.ensureBinary() is not supported on Android. Use NativeVpnService instead.",
      );
    } else {
      // Fallback for Linux/MacOS (assume installed in PATH or relative)
      return "sing-box";
    }
  }
}
