import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_gist_service.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mocktail/mocktail.dart';

class MockConfigManager extends Mock implements ConfigManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigGistService Tests', () {
    late ConfigGistService service;
    late MockConfigManager mockManager;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = ConfigGistService();
      mockManager = MockConfigManager();
    });

    test('fetchAndApplyConfigs should skip fetch if < 24h and configs exist',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          'last_config_fetch_timestamp', DateTime.now().millisecondsSinceEpoch);

      final dummy = VpnConfigWithMetrics(
        id: '1',
        rawConfig: 'vmess://',
        name: 'Dummy',
        addedDate: DateTime.now(),
      );
      when(() => mockManager.allConfigs).thenReturn([dummy]);

      final result =
          await service.fetchAndApplyConfigs(mockManager, force: false);
      expect(result, isTrue);

      verifyNever(() => mockManager.addConfigs(any(),
          checkBlacklist: any(named: 'checkBlacklist')));
    });

    test('fetchAndApplyConfigs should return false on network fail', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'last_config_fetch_timestamp',
        DateTime.now()
            .subtract(const Duration(hours: 25))
            .millisecondsSinceEpoch,
      );

      final dummy = VpnConfigWithMetrics(
        id: '1',
        rawConfig: 'vmess://',
        name: 'Dummy',
        addedDate: DateTime.now(),
      );
      when(() => mockManager.allConfigs).thenReturn([dummy]);
      when(() => mockManager.addConfigs(any(),
              checkBlacklist: any(named: 'checkBlacklist')))
          .thenAnswer((_) async => 1);

      final result =
          await service.fetchAndApplyConfigs(mockManager, force: false);
      expect(result, isFalse);
    });
  });
}
