import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_gist_service.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mocktail/mocktail.dart';

class MockConfigManager extends Mock implements ConfigManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigGistService Throttling', () {
    late ConfigGistService service;
    late MockConfigManager mockManager;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = ConfigGistService();
      mockManager = MockConfigManager();
    });

    test('fetchAndApplyConfigs should skip fetch if < 24h and configs exist', () async {
      final prefs = await SharedPreferences.getInstance();
      // Set last fetch to now
      await prefs.setInt('last_config_fetch_timestamp', DateTime.now().millisecondsSinceEpoch);

      // Mock manager has configs
      final dummy = VpnConfigWithMetrics(id: '1', rawConfig: 'vmess://', name: 'Dummy', addedDate: DateTime.now());
      when(() => mockManager.allConfigs).thenReturn([dummy]);

      // Should return true (skipped)
      final result = await service.fetchAndApplyConfigs(mockManager, force: false);
      expect(result, isTrue);

      // Verify addConfigs was NOT called
      verifyNever(() => mockManager.addConfigs(any(), checkBlacklist: any(named: 'checkBlacklist')));
    });

    test('fetchAndApplyConfigs should fetch if > 24h', () async {
      final prefs = await SharedPreferences.getInstance();
      // Set last fetch to 25h ago
      await prefs.setInt('last_config_fetch_timestamp', DateTime.now().subtract(const Duration(hours: 25)).millisecondsSinceEpoch);

      final dummy = VpnConfigWithMetrics(id: '1', rawConfig: 'vmess://', name: 'Dummy', addedDate: DateTime.now());
      when(() => mockManager.allConfigs).thenReturn([dummy]);
      // Mock addConfigs
      when(() => mockManager.addConfigs(any(), checkBlacklist: any(named: 'checkBlacklist')))
          .thenAnswer((_) async => 1);

      // Since real fetch calls network, and we can't easily mock http.get inside the singleton service without refactoring,
      // this test might try to make real network call if we proceed.
      // However, we can check if it proceeds past the throttle check.
      // If we can't mock http, we can't fully verify "fetch happened" vs "failed network".
      // But we can verify it didn't return early if we could inspect log or something.

      // Actually, if it tries to fetch, it will likely fail in test env (no internet/timeout) and return false (or true if backup exists).
      // If backup is empty, it returns false.

      final result = await service.fetchAndApplyConfigs(mockManager, force: false);
      // It should return false because network fetch fails and no backup.
      // If it skipped, it would return true.
      expect(result, isFalse);
    });

    test('fetchAndApplyConfigs should fetch if force is true even if < 24h', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_config_fetch_timestamp', DateTime.now().millisecondsSinceEpoch);

      final dummy = VpnConfigWithMetrics(id: '1', rawConfig: 'vmess://', name: 'Dummy', addedDate: DateTime.now());
      when(() => mockManager.allConfigs).thenReturn([dummy]);
      when(() => mockManager.addConfigs(any(), checkBlacklist: any(named: 'checkBlacklist')))
          .thenAnswer((_) async => 1);

      final result = await service.fetchAndApplyConfigs(mockManager, force: true);
      // Should fail network (false) instead of skip (true)
      expect(result, isFalse);
    });
  });
}
