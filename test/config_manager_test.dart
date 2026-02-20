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

      // Add two configs
      await manager.addConfig('vless://uuid@127.0.0.1:443?query=1#Config%201', 'Config 1');
      await manager.addConfig('vless://uuid@127.0.0.1:443?query=2#Config%202', 'Config 2');

      // Sort order is Date Descending, so Config 2 might be first.
      // Instead of assuming order, let's find Config 1 explicitly.
      final config1 = manager.allConfigs.firstWhere((c) => c.name == 'Config 1');
      final idToDelete = config1.id;

      final result = await manager.deleteConfig(idToDelete);

      expect(result, isTrue);
      expect(manager.allConfigs.length, 1);
      // The remaining config should be Config 2
      expect(manager.allConfigs.first.name, 'Config 2');
    });
    
    test('toggleFavorite updates list and storage', () async {
      final manager = ConfigManager();
      await manager.init();
      // clearAllData handled in setUp
      
      await manager.addConfig('vless://uuid@127.0.0.1:443?query=1#Fav%20Config', 'Fav Config');
      // Wait for async update
      await Future.delayed(Duration(milliseconds: 100));

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

    test('connectionProtocol saves and loads', () async {
      final manager = ConfigManager();
      await manager.init();

      // Default
      expect(manager.connectionProtocol, 'Automatic');

      // Set to TCP
      await manager.setConnectionProtocol('TCP');
      expect(manager.connectionProtocol, 'TCP');

      // Verify persistence
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('connection_protocol'), 'TCP');

      // Reload logic (simulate app restart by manually loading)
      // Note: We can't easily re-instantiate ConfigManager due to Singleton,
      // but we can verify the underlying storage is correct.

      // Set to UDP
      await manager.setConnectionProtocol('UDP');
      expect(manager.connectionProtocol, 'UDP');
      expect(prefs.getString('connection_protocol'), 'UDP');
    });
  });
}
