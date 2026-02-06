import 'dart:async';

class TestTimeouts {
  // Maximum durations for complete test suites
  static const Duration quickHealthCheck = Duration(seconds: 8);
  static const Duration fullHealthCheck = Duration(seconds: 15);
  static const Duration pingCheck = Duration(seconds: 5);
  static const Duration stabilityTest = Duration(seconds: 30);
  static const Duration speedTestSingle = Duration(seconds: 25);
  static const Duration adaptiveSpeedTest = Duration(seconds: 45);
  static const Duration configLoad = Duration(seconds: 35);
  
  // Individual operation timeouts
  static const Duration httpRequest = Duration(seconds: 8);
  static const Duration dnsResolution = Duration(seconds: 3);
  static const Duration tcpHandshake = Duration(seconds: 6);
  static const Duration sslHandshake = Duration(seconds: 5);
  
  // Helper to timeout any future
  static Future<T> withTimeout<T>(
    Future<T> future, {
    required Duration timeout,
    T Function()? onTimeout,
  }) async {
    try {
      return await future.timeout(timeout);
    } on TimeoutException {
      if (onTimeout != null) return onTimeout();
      rethrow;
    }
  }
}
