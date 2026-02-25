import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';
import 'package:ivpn_new/services/testers/ephemeral_tester.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Needed for mocking prefs

class MockEphemeralTester extends Mock implements EphemeralTester {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // Initialize binding for SharedPreferences

  group('ConfigManager Smart Logic', () {
    late ConfigManager configManager;
    late MockEphemeralTester mockTester;

    setUp(() async {
      SharedPreferences.setMockInitialValues({}); // Mock SharedPreferences
      configManager = ConfigManager();
      mockTester = MockEphemeralTester();
      await configManager.init(); // Properly init
    });

    test('markInvalid should set failureCount to 99 and kill isAlive', () async {
      // 1. Setup config
      const testId = "test_invalid_1";
      final config = VpnConfigWithMetrics(
        id: testId,
        rawConfig: "vless://test",
        name: "Test Config",
        failureCount: 0,
        isAlive: true,
      );

      // Inject manually via public API (addConfig triggers isolate, but in test env compute runs in same isolate usually or we wait)
      await configManager.addConfig(config.rawConfig, config.name);

      // Wait for async add
      await Future.delayed(const Duration(milliseconds: 100));

      // Retrieve the added config (ID generation in addConfigs is dynamic, so we find by name/raw)
      var added = configManager.allConfigs.firstWhere((c) => c.rawConfig == config.rawConfig);
      expect(added.isAlive, isTrue);
      expect(added.failureCount, 0);

      // 2. Call markInvalid
      await configManager.markInvalid(added.id);

      // 3. Verify
      var updated = configManager.allConfigs.firstWhere((c) => c.id == added.id);
      expect(updated.failureCount, 99);
      expect(updated.isAlive, isFalse);
      expect(updated.lastFailedStage, "Invalid_Config");
    });

    test('evaluateAutoSwitch triggers switch if current ping is bad (>400ms) and better candidate exists', () async {
      // 1. Setup Configs
      final badConfig = VpnConfigWithMetrics(
        id: 'bad',
        rawConfig: 'vless://bad',
        name: 'Bad',
        addedDate: DateTime.now(),
      ).updateMetrics(deviceId: configManager.currentDeviceId, ping: 500);

      final goodConfig = VpnConfigWithMetrics(
        id: 'good',
        rawConfig: 'vless://good',
        name: 'Good',
        addedDate: DateTime.now(),
      ).updateMetrics(deviceId: configManager.currentDeviceId, ping: 100);

      // 2. Inject into manager
      configManager.allConfigs = [badConfig, goodConfig];
      configManager.validatedConfigs = [goodConfig, badConfig]; // Sorted by score/ping
      configManager.selectConfig(badConfig);
      configManager.setConnected(true);
      configManager.isAutoSwitchEnabled = true;

      // Populate reserve list to ensure _performAutoSwitch picks 'good' immediately without funnel
      configManager.reserveList = [goodConfig];

      // 3. Spy on autoSwitch callback
      bool switched = false;
      configManager.onAutoSwitch = (config) {
        switched = true;
      };

      // 4. Trigger evaluation
      await configManager.evaluateAutoSwitch(500);

      // 5. Verify
      expect(switched, isTrue);
      expect(configManager.selectedConfig?.id, 'good');
    });

    test('evaluateAutoSwitch does NOT switch if current ping is acceptable (<300ms)', () async {
       final okayConfig = VpnConfigWithMetrics(
        id: 'okay',
        rawConfig: 'vless://okay',
        name: 'Okay',
        addedDate: DateTime.now(),
      ).updateMetrics(deviceId: configManager.currentDeviceId, ping: 200);

      final goodConfig = VpnConfigWithMetrics(
        id: 'good',
        rawConfig: 'vless://good',
        name: 'Good',
        addedDate: DateTime.now(),
      ).updateMetrics(deviceId: configManager.currentDeviceId, ping: 100);

      configManager.allConfigs = [okayConfig, goodConfig];
      configManager.validatedConfigs = [goodConfig, okayConfig];
      configManager.reserveList = [goodConfig];
      configManager.selectConfig(okayConfig);
      configManager.setConnected(true);
      configManager.isAutoSwitchEnabled = true;

      bool switched = false;
      configManager.onAutoSwitch = (_) => switched = true;

      await configManager.evaluateAutoSwitch(200);

      expect(switched, isFalse);
    });
  });
}
