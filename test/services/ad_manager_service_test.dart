import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ivpn_new/services/ad_manager_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdManagerService Tests', () {
    late AdManagerService adManager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      adManager = AdManagerService();
    });

    test('initialize loads empty cache and applies default fallback', () async {
      await adManager.initialize();
      // Initially, it might apply a fallback if no cache or network
      expect(adManager.configNotifier.value, isNotNull);
    });

    test('fetchLatestAds tries to download config', () async {
      // It uses real HTTP request so we just verify it doesn't crash
      // and properly handles exceptions/updates state.
      await adManager.initialize();
      await adManager.fetchLatestAds();

      // Because it might succeed or fail depending on network,
      // we just want to ensure config is not completely null.
      expect(adManager.configNotifier.value, isNotNull);
    });
  });
}
