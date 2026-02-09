import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ConfigManager Tests', () {
    test('Singleton pattern works', () {
      final instance1 = ConfigManager();
      final instance2 = ConfigManager();
      expect(identical(instance1, instance2), isTrue);
    });

    test('addConfig saves to SharedPreferences', () async {
      final manager = ConfigManager();
      await manager.init(fetchRemote: false);

      await manager.addConfig('vless://test#Test%20Config', 'Test Config');

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
      await manager.init(fetchRemote: false);
      await manager.clearAllData();

      await manager.addConfig('vless://test1#Config1', 'Config 1');
      await manager.addConfig('vless://test2#Config2', 'Config 2');

      // Check if added
      expect(manager.allConfigs.length, 2);

      final idToDelete = manager.allConfigs.firstWhere((c) => c.name == 'Config1').id;
      final result = await manager.deleteConfig(idToDelete);

      expect(result, isTrue);
      expect(manager.allConfigs.length, 1);
      expect(manager.allConfigs.first.name, 'Config2');
    });
    
    test('toggleFavorite updates list and storage', () async {
      final manager = ConfigManager();
      await manager.init(fetchRemote: false);
      await manager.clearAllData();
      
      await manager.addConfig('vless://test#FavConfig', 'Fav Config');
      
      expect(manager.allConfigs.first.isFavorite, isFalse);
      
      await manager.toggleFavorite(manager.allConfigs.first.id);
      expect(manager.allConfigs.first.isFavorite, isTrue);
      expect(manager.favoriteConfigs.length, 1);
      
      await manager.toggleFavorite(manager.allConfigs.first.id);
      expect(manager.allConfigs.first.isFavorite, isFalse);
      expect(manager.favoriteConfigs.isEmpty, isTrue);
    });
    
    test('getBestConfig returns valid config or null', () async {
      final manager = ConfigManager();
      await manager.init(fetchRemote: false);
      await manager.clearAllData();
      
      var best = await manager.getBestConfig();
      expect(best, isNull);
      
      await manager.addConfig('vless://test', 'Best Config');
      best = await manager.getBestConfig();
      expect(best, isNotNull);
    });
  });
}
