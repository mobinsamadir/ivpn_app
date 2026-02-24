import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mocks for channels used by dependencies
  const MethodChannel vpnChannel = MethodChannel('com.example.ivpn/vpn');
  const MethodChannel pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ConfigManager().clearAllData();

    // Mock VPN Channel (unused if performConnection: false, but good to have)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      vpnChannel,
      (MethodCall methodCall) async {
        return null;
      },
    );

    // Mock Path Provider (used by AdvancedLogger)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory' || methodCall.method == 'getTemporaryDirectory') {
          return '/tmp';
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(vpnChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProviderChannel, null);
  });

  group('ConfigManager Smart Logic', () {
    test('Skip Logic: Selects next valid config and wraps around', () async {
      final manager = ConfigManager();
      // Add 3 configs
      await manager.addConfigs([
        'vless://uuid@1.1.1.1:443?query=1#Config1', // Index 0
        'vless://uuid@2.2.2.2:443?query=1#Config2', // Index 1
        'vless://uuid@3.3.3.3:443?query=1#Config3', // Index 2
      ]);

      await Future.delayed(Duration.zero);

      // Simulate validation (set pings)
      // Config 1: Alive
      await manager.updateConfigMetrics(manager.allConfigs.firstWhere((c) => c.name == 'Config1').id, ping: 100);
      // Config 2: Dead (Ping -1)
      await manager.updateConfigMetrics(manager.allConfigs.firstWhere((c) => c.name == 'Config2').id, ping: -1);
      // Config 3: Alive
      await manager.updateConfigMetrics(manager.allConfigs.firstWhere((c) => c.name == 'Config3').id, ping: 200);

      // Select Config 1
      manager.selectConfig(manager.allConfigs.firstWhere((c) => c.name == 'Config1'));
      expect(manager.selectedConfig?.name, 'Config1');

      // Skip -> Should skip Config 2 (Dead) and go to Config 3
      // We disable connection to isolate selection logic
      await manager.skipToNext(performConnection: false);

      expect(manager.selectedConfig?.name, 'Config3');

      // Skip again -> Should wrap around to Config 1
      await manager.skipToNext(performConnection: false);
      expect(manager.selectedConfig?.name, 'Config1');
    });

    test('Skip Logic: Handles empty list gracefully', () async {
      final manager = ConfigManager();
      await manager.clearAllData();

      await manager.skipToNext(performConnection: false); // Should not crash
      expect(manager.selectedConfig, isNull);
    });

    test('Favorites Logic: Persists correctly', () async {
       final manager = ConfigManager();
       await manager.addConfigs(['vless://uuid@1.1.1.1:443?query=1#FavTest']);
       await Future.delayed(Duration.zero);

       final config = manager.allConfigs.first;

       expect(config.isFavorite, isFalse);

       await manager.toggleFavorite(config.id);
       expect(manager.allConfigs.first.isFavorite, isTrue);

       final prefs = await SharedPreferences.getInstance();
       final jsonStr = prefs.getString('vpn_configs');
       expect(jsonStr, isNotNull);
       expect(jsonStr!.contains('"isFavorite":true'), isTrue);
    });
  });
}
