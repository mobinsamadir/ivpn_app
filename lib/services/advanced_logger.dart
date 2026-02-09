// ignore_for_file: avoid_print

class AdvancedLogger {
  static Future<void> init() async {}
  static void info(String message, {Map? metadata}) {}
  static void error(String message, {Object? error, StackTrace? stackTrace}) {}
  static void warn(String message, {Object? error, StackTrace? stackTrace}) {
    print('[WARN] $message');
    if (error != null) {
      print('Error: $error');
      if (stackTrace != null) print('Stack: $stackTrace');
    }
  }
}
