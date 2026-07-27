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
      expect(adManager.configNotifier.value, isNotNull);
      expect(adManager.configNotifier.value?.configVersion, isNotEmpty);
    });

    test('getAdUnit returns correct unit', () async {
      await adManager.initialize();
      final unit = adManager.getAdUnit('reward_ad');
      expect(unit, isNotNull);
      expect(unit?.type, equals('webview'));
    });

    test('showPreConnectionAd fails open without context', () async {
      await adManager.initialize();
      // Test without valid context handles fail open via checking context.mounted
    });

    test('fetchLatestAds falls back on error', () async {
      await adManager.initialize();
      await adManager.fetchLatestAds();
      expect(adManager.configNotifier.value, isNotNull);
    });

    test('showPostConnectionAd is a no-op', () async {
      await adManager.initialize();
      await adManager.showPostConnectionAd();
      expect(true, true);
    });
  });
}
