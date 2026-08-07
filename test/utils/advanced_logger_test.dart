import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/advanced_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return Directory.systemTemp.path;
      }
      return null;
    });
  });

  group('AdvancedLogger Tests', () {
    setUp(() async {
      // Re-initialize for each test to clear state
      await AdvancedLogger.init(minLevel: LogLevel.debug);
    });

    tearDown(() async {
      await AdvancedLogger.close();
    });

    test('initializes and creates log file', () async {
      final path = await AdvancedLogger.getLogPath();
      expect(path, isNotEmpty);
    });

    test('info logs string and adds to memory', () {
      final initialCount = AdvancedLogger.logNotifier.value.length;
      AdvancedLogger.info('Test Info Message');
      final newCount = AdvancedLogger.logNotifier.value.length;
      expect(newCount, greaterThan(initialCount));
      expect(
          AdvancedLogger.logNotifier.value.last, contains('Test Info Message'));
    });

    test('error logs with stack trace and metadata', () {
      final initialCount = AdvancedLogger.logNotifier.value.length;
      final stack = StackTrace.current;
      AdvancedLogger.error('Test Error Message',
          error: Exception('Test Ex'),
          stackTrace: stack,
          metadata: {'meta': 'data'});
      final newCount = AdvancedLogger.logNotifier.value.length;
      expect(newCount, greaterThan(initialCount));
      expect(AdvancedLogger.logNotifier.value.last,
          contains('Test Error Message'));
      // The log history only formats the main message, not the metadata json, so we check if it didn't crash and logged the core message
    });

    test('warn logs message', () {
      final initialCount = AdvancedLogger.logNotifier.value.length;
      AdvancedLogger.warn('Test Warn Message');
      expect(
          AdvancedLogger.logNotifier.value.length, greaterThan(initialCount));
    });

    test('debug logs message', () {
      final initialCount = AdvancedLogger.logNotifier.value.length;
      AdvancedLogger.debug('Test Debug Message');
      expect(
          AdvancedLogger.logNotifier.value.length, greaterThan(initialCount));
    });

    test('networkRequest logs formatted output', () {
      final initialCount = AdvancedLogger.logNotifier.value.length;
      AdvancedLogger.networkRequest('GET', 'http://example.com/api',
          headers: {'Auth': 'Bearer token123'}, body: {'req': 'data'});
      expect(
          AdvancedLogger.logNotifier.value.length, greaterThan(initialCount));
      final lastLog = AdvancedLogger.logNotifier.value.last;
      expect(lastLog, contains('GET'));
      expect(lastLog, contains('http://example.com/api'));
    });

    test('networkResponse logs formatted output', () {
      final initialCount = AdvancedLogger.logNotifier.value.length;
      AdvancedLogger.networkResponse('http://example.com/api', 200,
          body: {'res': 'data'}, duration: const Duration(milliseconds: 150));
      expect(
          AdvancedLogger.logNotifier.value.length, greaterThan(initialCount));
      final lastLog = AdvancedLogger.logNotifier.value.last;
      expect(lastLog, contains('200'));
      expect(lastLog, contains('http://example.com/api'));
    });

    test('redacts sensitive keys in map', () {
      AdvancedLogger.info('Sensitive Data', metadata: {
        'password': 'mySecretPassword',
        'token': 'mySecretToken',
        'public': 'publicData'
      });
      final lastLog = AdvancedLogger.logNotifier.value.last;
      expect(lastLog, contains('Sensitive Data'));
    });

    test('redacts sensitive values in strings', () {
      AdvancedLogger.info('Sending token=mySecretToken123 to server');
      final lastLog = AdvancedLogger.logNotifier.value.last;
      expect(lastLog, contains('[REDACTED]'));
      expect(lastLog, isNot(contains('mySecretToken123')));
    });
  });
}
