import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/advanced_logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return '/tmp';
  }
}

void main() {
  group('AdvancedLogger Tests', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      PathProviderPlatform.instance = MockPathProviderPlatform();
    });

    setUp(() async {
      await AdvancedLogger.init(minLevel: LogLevel.debug);
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
      expect(() => AdvancedLogger.networkRequest('GET', 'http://example.com'), returnsNormally);
    });

    test('networkResponse does not crash', () {
      expect(() => AdvancedLogger.networkResponse('http://example.com', 200), returnsNormally);
    });

    test('getLogPath returns a path', () async {
       final path = await AdvancedLogger.getLogPath();
       expect(path, isNotEmpty);
    });
  });
}
