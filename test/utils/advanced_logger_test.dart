import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/advanced_logger.dart';

void main() {
  group('AdvancedLogger Tests', () {
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
  });
}
