import 'dart:developer' as developer;
import 'dart:io';

class AppLogger {
  static void debug(String message, {String name = 'IVPN'}) {
    developer.log('🔍 $message', name: name);
  }
  
  static void info(String message) {
    stdout.writeln('ℹ️ [IVPN] $message');
  }
  
  static void error(String message, {dynamic error, StackTrace? stackTrace}) {
    stderr.writeln('❌ [IVPN ERROR] $message');
    if (error != null) stderr.writeln('   Error: $error');
    if (stackTrace != null) stderr.writeln('   Stack: $stackTrace');
  }
  
  static void speedTest(String message) {
    developer.log('⚡ [SPEED_TEST] $message', name: 'SPEED');
    stdout.writeln('🚀 [SPEED] $message');
  }
  
  static void stability(String message) {
    developer.log('📊 [STABILITY] $message', name: 'STABILITY');
    stdout.writeln('📊 [STABILITY] $message');
  }
}
