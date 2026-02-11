import 'package:flutter/foundation.dart';

class AdvancedLogger {
  static Future<void> init() async {}
  static void info(String message, {Map? metadata}) {}
  static void warn(String message, {Object? error, StackTrace? stackTrace}) {
    debugPrint("⚠️ [WARN] $message");
    if (error != null) debugPrint("Error: $error");
  }
  static void error(String message, {Object? error, StackTrace? stackTrace}) {}
}
