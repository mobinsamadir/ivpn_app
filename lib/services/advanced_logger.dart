class AdvancedLogger {
  static Future<void> init() async {}
  static void info(String message, {Map? metadata}) {}
  static void error(String message, {Object? error, StackTrace? stackTrace}) {}
}

