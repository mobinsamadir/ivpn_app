import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ivpn_new/services/storage_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageInterface Tests', () {
    late SharedPreferencesStorage storage;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = SharedPreferencesStorage();
    });

    test('getString returns null if not set', () async {
      final result = await storage.getString('test_key');
      expect(result, isNull);
    });

    test('setString and getString work correctly', () async {
      await storage.setString('test_key', 'test_value');
      final result = await storage.getString('test_key');
      expect(result, 'test_value');
    });

    test('getBool returns null if not set', () async {
      final result = await storage.getBool('test_bool');
      expect(result, isNull);
    });

    test('setBool and getBool work correctly', () async {
      await storage.setBool('test_bool', true);
      final result = await storage.getBool('test_bool');
      expect(result, isTrue);
    });

    test('remove works correctly', () async {
      await storage.setString('test_key', 'test_value');
      await storage.remove('test_key');
      final result = await storage.getString('test_key');
      expect(result, isNull);
    });
  });
}
