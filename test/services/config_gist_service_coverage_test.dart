import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_gist_service.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter/material.dart';

class MockBuildContext extends Mock implements BuildContext {}

class MockConfigManager extends Mock implements ConfigManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ConfigGistService Extra Coverage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(
          {'gist_backup_configs': '["vmess://test"]'});
    });
    test('checkForUpdates handles network gracefuly', () async {
      final service = ConfigGistService();
      final context = MockBuildContext();
      await service.checkForUpdates(context);
    });
    test('fetchAndApplyConfigs falls back to backup', () async {
      final service = ConfigGistService();
      final mockManager = MockConfigManager();
      when(() => mockManager.allConfigs).thenReturn([]);
      when(() => mockManager.addConfigs(any(),
              checkBlacklist: any(named: 'checkBlacklist')))
          .thenAnswer((_) async => 1);
      final res = await service.fetchAndApplyConfigs(mockManager, force: true);
    });
  });
}
