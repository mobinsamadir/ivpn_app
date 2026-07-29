import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/advanced_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdvancedLogger Tests', () {
    setUp(() async {
      // Intentionally not awaiting init to force initialization errors
      // await AdvancedLogger.init(minLevel: LogLevel.debug);
    });

    tearDown(() async {
      await AdvancedLogger.close();
    });

    test('info does not crash', () {
      expect(() => AdvancedLogger.info('Test Info'), returnsNormally);
    });

    test('error does not crash', () {
      expect(() => AdvancedLogger.error('Test Error'), returnsNormally);
    });

    test('warn does not crash', () {
      expect(() => AdvancedLogger.warn('Test Warn'), returnsNormally);
    });

    test('debug does not crash', () {
      expect(() => AdvancedLogger.debug('Test Debug'), returnsNormally);
    });

    test('networkRequest does not crash', () {
      expect(() => AdvancedLogger.networkRequest('GET', 'http://example.com'),
          returnsNormally);
    });

    test('networkResponse does not crash', () {
      expect(() => AdvancedLogger.networkResponse('http://example.com', 200),
          returnsNormally);
    });
  });
}
