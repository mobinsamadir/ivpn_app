import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ivpn_new/services/access_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccessManager accessManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    accessManager = AccessManager();
    await accessManager.clearAccess();

    // Default clock to a fixed time for consistency
    final fixedTime = DateTime(2023, 1, 1, 12, 0, 0);
    accessManager.setClock(() => fixedTime);
  });

  group('AccessManager Tests', () {
    test('Initialization: Default state (No Access)', () async {
      await accessManager.init();
      expect(accessManager.hasAccess, isFalse);
      expect(accessManager.remainingTime, Duration.zero);
      expect(accessManager.expirationDate, isNull);
    });

    test('addTime: Adds duration correctly from fresh state', () async {
      final now = DateTime(2023, 1, 1, 12, 0, 0);
      accessManager.setClock(() => now);

      await accessManager.addTime(const Duration(hours: 1));

      expect(accessManager.hasAccess, isTrue);
      expect(accessManager.expirationDate, now.add(const Duration(hours: 1)));
      expect(accessManager.remainingTime, const Duration(hours: 1));
    });

    test('addTime: Extends existing duration', () async {
      final now = DateTime(2023, 1, 1, 12, 0, 0);
      accessManager.setClock(() => now);

      // Add 1 hour -> 13:00
      await accessManager.addTime(const Duration(hours: 1));

      // Advance time by 6 seconds to bypass double-reward check
      final later = now.add(const Duration(seconds: 6));
      accessManager.setClock(() => later);

      // Add another hour -> Should add to existing expiry (13:00) => 14:00
      await accessManager.addTime(const Duration(hours: 1));

      expect(accessManager.expirationDate, now.add(const Duration(hours: 2)));
    });

    test('Double Reward Prevention: Rapid adds within 5s fail', () async {
      final now = DateTime(2023, 1, 1, 12, 0, 0);
      accessManager.setClock(() => now);

      // First add -> 13:00
      await accessManager.addTime(const Duration(hours: 1));
      final firstExpiry = accessManager.expirationDate;

      // Advance by 2 seconds (still < 5s)
      final tooSoon = now.add(const Duration(seconds: 2));
      accessManager.setClock(() => tooSoon);

      // Second add -> Should be ignored
      await accessManager.addTime(const Duration(hours: 1));

      expect(accessManager.expirationDate, firstExpiry);
    });

    test('Double Reward Prevention: Adds allowed after 5s', () async {
      final now = DateTime(2023, 1, 1, 12, 0, 0);
      accessManager.setClock(() => now);

      // First add -> 13:00
      await accessManager.addTime(const Duration(hours: 1));

      // Advance by 6 seconds (> 5s)
      final allowedTime = now.add(const Duration(seconds: 6));
      accessManager.setClock(() => allowedTime);

      // Second add -> Should work. Adds to existing expiry (13:00) -> 14:00.
      await accessManager.addTime(const Duration(hours: 1));

      expect(accessManager.expirationDate, now.add(const Duration(hours: 2)));
    });

    test('hasAccess: False if time expired', () async {
       final now = DateTime(2023, 1, 1, 12, 0, 0);
       accessManager.setClock(() => now);

       // Add 30 mins -> 12:30
       await accessManager.addTime(const Duration(minutes: 30));
       expect(accessManager.hasAccess, isTrue);

       // Advance time to 12:31
       final future = now.add(const Duration(minutes: 31));
       accessManager.setClock(() => future);

       expect(accessManager.hasAccess, isFalse);
       expect(accessManager.remainingTime, Duration.zero);
    });

    test('Restoration: Init restores from SharedPreferences', () async {
       final storedTime = DateTime(2024, 1, 1, 12, 0, 0);
       SharedPreferences.setMockInitialValues({
         'vpn_access_expiration': storedTime.millisecondsSinceEpoch
       });

       // We need to re-create or reset logic, but since it's singleton, we just call init()
       // But init() relies on retrieving fresh prefs instance.
       // SharedPreferences.getInstance() returns the same future usually.
       // But setMockInitialValues resets the underlying map for the next getInstance call?
       // Actually, SharedPreferences.getInstance() caches the instance.
       // So we might need to rely on the fact that we set mock values BEFORE the very first getInstance in setUp?
       // Wait, setUp runs before EVERY test.
       // So for this specific test, we should set mock values inside the test BEFORE calling init.

       // However, setUp already called AccessManager(), which might have called init? No, init is explicit.
       // But we called clearAccess() in setUp which gets instance.

       // Let's try setting values here.
       SharedPreferences.setMockInitialValues({
         'vpn_access_expiration': storedTime.millisecondsSinceEpoch
       });

       // We need to force reload from prefs.
       // AccessManager.init() does `await SharedPreferences.getInstance()`.
       // If the instance is cached, it might have old values?
       // `setMockInitialValues` updates the backing store for the mock implementation.
       // So subsequent reads should see it.

       await accessManager.init();

       expect(accessManager.expirationDate, storedTime);
       expect(accessManager.hasAccess, isTrue); // Assuming clock is default (2023) vs stored (2024)
    });
  });
}
