import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ivpn_new/services/time_wallet_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimeWalletService Tests', () {
    late TimeWalletService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = TimeWalletService();
    });

    test('Initial state should have 0 remaining seconds', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init();
      expect(service.hasTime, isFalse);
      expect(service.remainingSeconds, equals(0));
    });

    test('rewardTime adds 1 hour to the wallet', () async {
      // Force initial value so it resets logic instead of using cache
      SharedPreferences.setMockInitialValues({});
      await service.init();

      // Ensure we start from 0 for testing purposes
      await service.consumeTime(service.remainingSeconds + 100);

      await service.rewardTime();
      expect(service.hasTime, isTrue);
      // Because network sync adds a bit of delay, expect around 3600
      expect(service.remainingSeconds, inInclusiveRange(3590, 3600));
    });

    test('consumeTime reduces time correctly', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init();

      await service.consumeTime(service.remainingSeconds + 100);
      await service.rewardTime();

      await service.consumeTime(1800); // consume half an hour
      expect(service.remainingSeconds, inInclusiveRange(1790, 1800));
    });

    test('consumeTime to zero or below triggers expiration', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init();

      await service.consumeTime(service.remainingSeconds + 100);
      await service.rewardTime();

      await service.consumeTime(4000); // consume more than rewarded
      expect(service.hasTime, isFalse);
      expect(service.remainingSeconds, equals(0));
    });
  });
}
