import 'dart:developer' as developer;

class AppLogger {
  static void debug(String message) {
    developer.log('🔍 $message', name: 'IVPN');
    print('[DEBUG] $message');
  }
  
  static void info(String message) {
    print('ℹ️  $message');
  }
  
  static void error(String message, {dynamic error, StackTrace? stackTrace}) {
    print('❌ $message');
    if (error != null) print('   Error: $error');
    if (stackTrace != null) print('   Stack: $stackTrace');
  }
  
  static void speedTest(String message) {
    print('⚡ [SPEED_TEST] $message');
  }
  
  static void stability(String message) {
    print('📊 [STABILITY] $message');
  }
}
