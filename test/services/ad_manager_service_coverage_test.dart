import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/ad_manager_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('AdManagerService extra coverage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('load from cache handles exception', () async {
      final service = AdManagerService();
      await service.initialize();
      service.configNotifier.value = null;
      await service.fetchLatestAds();
      expect(service.configNotifier.value, isNotNull);
    });

    test('getAdUnit works properly', () async {
      final service = AdManagerService();
      await service.initialize();
      expect(service.getAdUnit('reward_ad'), isNotNull);
    });

    test('showPostConnectionAd does not throw', () async {
      final service = AdManagerService();
      await service.showPostConnectionAd();
      expect(true, isTrue);
    });
  });
}
