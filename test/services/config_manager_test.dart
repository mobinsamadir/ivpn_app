import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ConfigManager().clearAllData();
  });

  group('ConfigManager Tests', () {
    test('Singleton pattern works', () {
      final instance1 = ConfigManager();
      final instance2 = ConfigManager();
      expect(identical(instance1, instance2), isTrue);
    });

    test('addConfig saves to SharedPreferences', () async {
      final manager = ConfigManager();
      await manager.init();

      // Use proper URI format
      await manager.addConfig('vless://uuid@127.0.0.1:443?query=1#Test%20Config', 'Ignored Name');

      expect(manager.allConfigs.length, 1);
      expect(manager.allConfigs.first.name, 'Test Config');
      
      // Verify persistence
      final prefs = await SharedPreferences.getInstance();
      final savedString = prefs.getString('vpn_configs');
      expect(savedString, isNotNull);
      expect(savedString!.contains('Test Config'), isTrue);
    });

    test('deleteConfig removes from list and storage', () async {
      final manager = ConfigManager();
      await manager.init();
      // clearAllData handled in setUp

      await manager.addConfig('vless://uuid@127.0.0.1:443?query=1#Config%201', 'Config 1');
      await manager.addConfig('vless://uuid@127.0.0.1:443?query=1#Config%202', 'Config 2');

      // Find Config 1 by name to ensure we delete the correct one regardless of sort order
      final config1 = manager.allConfigs.firstWhere((c) => c.name == 'Config 1');
      final result = await manager.deleteConfig(config1.id);

      expect(result, isTrue);
      expect(manager.allConfigs.length, 1);
      expect(manager.allConfigs.first.name, 'Config 2');
    });
    
    test('toggleFavorite updates list and storage', () async {
      final manager = ConfigManager();
      await manager.init();
      // clearAllData handled in setUp
      
      await manager.addConfig('vless://uuid@127.0.0.1:443?query=1#Fav%20Config', 'Fav Config');
      final config = manager.allConfigs.first;
      
      expect(config.isFavorite, isFalse);
      
      await manager.toggleFavorite(config.id);
      expect(manager.allConfigs.first.isFavorite, isTrue);
      expect(manager.favoriteConfigs.length, 1);
      
      await manager.toggleFavorite(config.id);
      expect(manager.allConfigs.first.isFavorite, isFalse);
      expect(manager.favoriteConfigs.isEmpty, isTrue);
    });
    
    test('getBestConfig returns valid config or null', () async {
      final manager = ConfigManager();
      await manager.init();
      // clearAllData handled in setUp
      
      var best = await manager.getBestConfig();
      expect(best, isNull);
      
      await manager.addConfig('vless://uuid@127.0.0.1:443?query=1#Best%20Config', 'Best Config');
      best = await manager.getBestConfig();
      expect(best, isNotNull);
    });

    test('Stress Test: Add 500+ configs', () async {
      final manager = ConfigManager();
      await manager.init();

      final List<String> configs = [];
      for (int i = 0; i < 500; i++) {
        configs.add('vless://uuid@127.0.0.1:443?query=1#Config_$i');
      }

      final count = await manager.addConfigs(configs);

      expect(count, 500);
      expect(manager.allConfigs.length, 500);
      // Note: Sort order might affect last element if auto-sort is enabled.
      // Newly added configs usually have similar score/date, so order might be preserved or reversed.
      // We check that it contains specific one.
      expect(manager.allConfigs.any((c) => c.name == 'Config_0'), isTrue);
      expect(manager.allConfigs.any((c) => c.name == 'Config_499'), isTrue);

      // Verify persistence
      final prefs = await SharedPreferences.getInstance();
      final savedString = prefs.getString('vpn_configs');
      expect(savedString, isNotNull);
      expect(savedString!.length, greaterThan(10000));
    });
  });
}
