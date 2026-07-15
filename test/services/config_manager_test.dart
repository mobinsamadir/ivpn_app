import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ivpn_new/services/storage_interface.dart';

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
      await manager.addConfig(
        'vless://uuid@127.0.0.1:443?query=1#Test%20Config',
        'Ignored Name',
      );

      expect(manager.allConfigs.length, 1);
      expect(manager.allConfigs.first.name, 'Test Config');

      // Verify persistence
      // Note: Because saving is now a fire-and-forget compute task,
      // we need to wait briefly for it to complete in the background
      // before asserting on SharedPreferences.
      await Future.delayed(const Duration(milliseconds: 2000));

      final prefs = await SharedPreferences.getInstance();
      final savedString = prefs.getString('vpn_configs');
      expect(savedString, isNotNull);
      expect(savedString!.contains('Test Config'), isTrue);
    });

    test('deleteConfig removes from list and storage', () async {
      final manager = ConfigManager();
      await manager.init();
      // clearAllData handled in setUp

      await manager.addConfig(
        'vless://uuid@127.0.0.1:443?query=1#Config%201',
        'Config 1',
      );
      await manager.addConfig(
        'vless://uuid@127.0.0.1:443?query=1#Config%202',
        'Config 2',
      );

      // Find Config 1 by name to ensure we delete the correct one regardless of sort order
      final config1 = manager.allConfigs.firstWhere(
        (c) => c.name == 'Config 1',
      );
      final result = await manager.deleteConfig(config1.id);

      expect(result, isTrue);
      expect(manager.allConfigs.length, 1);
      expect(manager.allConfigs.first.name, 'Config 2');
    });

    test('toggleFavorite updates list and storage', () async {
      final manager = ConfigManager();
      await manager.init();
      // clearAllData handled in setUp

      await manager.addConfig(
        'vless://uuid@127.0.0.1:443?query=1#Fav%20Config',
        'Fav Config',
      );
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

      await manager.addConfig(
        'vless://uuid@127.0.0.1:443?query=1#Best%20Config',
        'Best Config',
      );
      best = await manager.getBestConfig();
      expect(best, isNotNull);
    });

    group('Split Tunneling Packages Persistence', () {
      test('Default value is an empty list', () async {
        final manager = ConfigManager();
        await manager.init();

        expect(manager.splitTunnelingPackages, isEmpty);
      });

      test('Setting value updates SharedPreferences with JSON', () async {
        final manager = ConfigManager();
        await manager.init();

        final packages = ['com.example.app', 'com.example.game'];
        manager.splitTunnelingPackages = packages;

        await Future.delayed(const Duration(milliseconds: 50));
        final prefs = await SharedPreferences.getInstance();
        final savedJson = prefs.getString('split_tunneling_packages');
        expect(savedJson, '["com.example.app","com.example.game"]');
      });

      test('Setting value calls notifyListeners', () async {
        final manager = ConfigManager();
        await manager.init();

        bool wasNotified = false;
        manager.addListener(() {
          wasNotified = true;
        });

        manager.splitTunnelingPackages = ['com.example.app'];

        expect(wasNotified, isTrue);
      });

      test('init() correctly parses valid JSON', () async {
        final manager = ConfigManager();
        await manager.clearAllData();
        manager.setStorage(SharedPreferencesStorage());
        SharedPreferences.setMockInitialValues({
          'split_tunneling_packages': '["com.app1","com.app2"]',
        });

        await manager.init();

        expect(manager.splitTunnelingPackages, ['com.app1', 'com.app2']);
      });

      test('init() handles corrupted JSON gracefully', () async {
        final manager = ConfigManager();
        await manager.clearAllData();
        manager.setStorage(SharedPreferencesStorage());
        SharedPreferences.setMockInitialValues({
          'split_tunneling_packages': 'invalid_json',
        });

        // This should not throw an exception
        await manager.init();

        expect(manager.splitTunnelingPackages, isEmpty);
      });
    });

    group('Kill Switch Settings Persistence', () {
      test('Default value is false', () async {
        final manager = ConfigManager();
        await manager.clearAllData();
        manager.setStorage(SharedPreferencesStorage());
        SharedPreferences.setMockInitialValues({});
        await manager.init();

        expect(manager.isKillSwitchEnabled, isFalse);
      });

      test('Setting value updates SharedPreferences correctly', () async {
        final manager = ConfigManager();
        await manager.clearAllData();
        manager.setStorage(SharedPreferencesStorage());
        SharedPreferences.setMockInitialValues({});
        await manager.init();

        manager.isKillSwitchEnabled = true;

        await Future.delayed(const Duration(milliseconds: 50));

        final prefs = await SharedPreferences.getInstance();
        final savedValue = prefs.getBool('kill_switch_enabled');
        expect(savedValue, isTrue);
      });

      test('Setting value calls notifyListeners', () async {
        final manager = ConfigManager();
        await manager.init();

        bool wasNotified = false;
        manager.addListener(() {
          wasNotified = true;
        });

        manager.isKillSwitchEnabled = true;

        expect(wasNotified, isTrue);
      });

      test('init() loads the saved state', () async {
        SharedPreferences.setMockInitialValues({'kill_switch_enabled': true});

        final manager = ConfigManager();
        await manager.init();

        expect(manager.isKillSwitchEnabled, isTrue);
      });
    });

    group('Auto Switch Settings Persistence', () {
      test('Default value is true', () async {
        final manager = ConfigManager();
        await manager.clearAllData();
        manager.setStorage(SharedPreferencesStorage());
        SharedPreferences.setMockInitialValues({});
        await manager.init();

        expect(manager.isAutoSwitchEnabled, isTrue);
      });

      test('Setting value updates SharedPreferences correctly', () async {
        final manager = ConfigManager();
        await manager.clearAllData();
        manager.setStorage(SharedPreferencesStorage());
        SharedPreferences.setMockInitialValues({});
        await manager.init();

        manager.isAutoSwitchEnabled = false;

        await Future.delayed(const Duration(milliseconds: 50));

        final prefs = await SharedPreferences.getInstance();
        final savedValue = prefs.getBool('auto_switch_enabled');
        expect(savedValue, isFalse);
      });
    });

    group('Config States (markSuccess, markFailure, markInvalid)', () {
      test('markSuccess resets failureCount and marks alive', () async {
        final manager = ConfigManager();
        await manager.clearAllData();
        await manager.addConfig(
          'vless://uuid@127.0.0.1:443?query=1#Test1',
          'Test1',
        );

        final config = manager.allConfigs.first;
        expect(config.failureCount, 0);

        await manager.markFailure(config.id);
        expect(manager.allConfigs.first.failureCount, 1);
        expect(manager.allConfigs.first.isAlive, isFalse);

        await manager.markSuccess(config.id);
        expect(manager.allConfigs.first.failureCount, 0);
        expect(manager.allConfigs.first.isAlive, isTrue);
      });

      test(
        'markInvalid sets failureCount to 99 and updates lastFailedStage',
        () async {
          final manager = ConfigManager();
          await manager.clearAllData();
          await manager.addConfig(
            'vless://uuid@127.0.0.1:443?query=1#Test1',
            'Test1',
          );

          final config = manager.allConfigs.first;
          await manager.markInvalid(config.id);

          expect(manager.allConfigs.first.failureCount, 99);
          expect(manager.allConfigs.first.isAlive, isFalse);
          expect(manager.allConfigs.first.lastFailedStage, 'Invalid_Config');
        },
      );
    });

    group('removeConfigs logic', () {
      test('removeConfigs with dead=true removes dead configs', () async {
        final manager = ConfigManager();
        await manager.clearAllData();

        await manager.addConfig(
          'vless://uuid@127.0.0.1:443?query=1#Alive',
          'Alive',
        );
        await manager.updateConfigMetrics(
          manager.allConfigs.firstWhere((c) => c.name == 'Alive').id,
          ping: 100,
        );
        await manager.addConfig(
          'vless://uuid@127.0.0.1:443?query=1#Dead',
          'Dead',
        );

        final deadConfig = manager.allConfigs.firstWhere(
          (c) => c.name == 'Dead',
        );

        // Mark as dead: failureCount >= 3
        await manager.markFailure(deadConfig.id);
        await manager.markFailure(deadConfig.id);
        await manager.markFailure(deadConfig.id);

        expect(manager.allConfigs.length, 2);

        await manager.removeConfigs(dead: true);

        expect(manager.allConfigs.length, 1);
        expect(manager.allConfigs.first.name, 'Alive');
      });
    });

    group('stopAllOperations', () {
      test('stopAllOperations sets flags and disconnects', () async {
        final manager = ConfigManager();
        await manager.clearAllData();

        expect(manager.userInitiatedDisconnect, isFalse);
        expect(manager.isGlobalStopRequested, isFalse);

        await manager.stopAllOperations();

        expect(manager.userInitiatedDisconnect, isTrue);
        expect(manager.isConnectionCancelled, isTrue);
        expect(manager.isGlobalStopRequested, isTrue);
        expect(manager.isConnected, isFalse);
        expect(manager.connectionStatus, 'Disconnected');
      });
    });

    group('skipToNext & Throttling Logic', () {
      test(
        'skipToNext intelligently cycles configs based on smart skip',
        () async {
          final manager = ConfigManager();
          await manager.clearAllData();

          await manager.addConfig(
            'vless://uuid@127.0.0.1:443?query=1#Skip1',
            'Skip1',
          );
          await manager.addConfig(
            'vless://uuid@127.0.0.1:443?query=1#Skip2',
            'Skip2',
          );

          // Both need currentPing > 0 to be valid candidates
          for (var c in manager.allConfigs) {
            // Need funnelStage to be > 0 and different scores to ensure predictability in skipToNext, or similar scores but stable addedDate.
            await manager.updateConfigDirectly(c.copyWith(funnelStage: 1));
            await manager.updateConfigMetrics(c.id, ping: 100);
          }

          // Force different addedDates so that sorting is stable
          manager.allConfigs[0] = manager.allConfigs[0].copyWith(addedDate: DateTime.fromMillisecondsSinceEpoch(1));
          manager.allConfigs[1] = manager.allConfigs[1].copyWith(addedDate: DateTime.fromMillisecondsSinceEpoch(2));

          manager.selectConfig(
            manager.allConfigs.firstWhere((c) => c.name == 'Skip1'),
          );

          final result = await manager.skipToNext(performConnection: false);
          expect(result, isTrue);
          expect(manager.selectedConfig?.name, 'Skip2');
        },
      );

      test(
        'notifyListenersThrottled defers notifications and batches updates',
        () async {
          final manager = ConfigManager();
          await manager.clearAllData();
          await manager.addConfig(
            'vless://uuid@127.0.0.1:443?query=1#Throttle1',
            'Throttle1',
          );

          int notificationCount = 0;
          manager.addListener(() {
            notificationCount++;
          });

          // Trigger multiple rapid metric updates which use notifyListenersThrottled internally
          final id = manager.allConfigs.first.id;
          await manager.updateConfigMetrics(id, ping: 100);
          await manager.updateConfigMetrics(id, ping: 200);
          await manager.updateConfigMetrics(id, ping: 300);

          // Before throttle ticks, notification shouldn't be spammed
          expect(notificationCount, 0);

          // Wait for throttle duration (500ms + some buffer)
          await Future.delayed(const Duration(milliseconds: 600));

          // Because of _safeNotifyListeners via addPostFrameCallback, it might just be direct in tests if scheduler is idle
          expect(notificationCount, greaterThanOrEqualTo(1));
        },
      );
    });

    group(
      'Further Methods Coverage (disconnectVpn, clearAllData, removeConfigs flags)',
      () {
        test('disconnectVpn sets states and disconnects', () async {
          final manager = ConfigManager();
          await manager.clearAllData();

          manager.setConnected(true, status: 'Connected');
          await manager.disconnectVpn();

          expect(manager.userInitiatedDisconnect, isTrue);
          expect(manager.isConnectionCancelled, isTrue);
          expect(manager.isConnected, isFalse);
          expect(manager.connectionStatus, 'Disconnected');
        });

        test(
          'clearAllData wipes all configs, caches, and selections',
          () async {
            final manager = ConfigManager();
            await manager.clearAllData();

            await manager.addConfig(
              'vless://uuid@127.0.0.1:443?query=1#Data1',
              'Data1',
            );
            manager.selectConfig(manager.allConfigs.first);

            expect(manager.allConfigs.length, 1);
            expect(manager.selectedConfig, isNotNull);

            await manager.clearAllData();

            expect(manager.allConfigs.length, 0);
            expect(manager.selectedConfig, isNull);
          },
        );

        test(
          'removeConfigs with weak=true removes high ping configs',
          () async {
            final manager = ConfigManager();
            await manager.clearAllData();

            await manager.addConfig(
              'vless://uuid@127.0.0.1:443?query=1#Normal',
              'Normal',
            );
            await manager.addConfig(
              'vless://uuid@127.0.0.1:443?query=1#Weak',
              'Weak',
            );

            final weakId =
                manager.allConfigs.firstWhere((c) => c.name == 'Weak').id;
            await manager.updateConfigMetrics(
              weakId,
              ping: 1600,
            ); // > 1500 threshold

            final normalId =
                manager.allConfigs.firstWhere((c) => c.name == 'Normal').id;
            await manager.updateConfigMetrics(normalId, ping: 100);

            expect(manager.allConfigs.length, 2);

            await manager.removeConfigs(weak: true);

            expect(manager.allConfigs.length, 1);
            expect(manager.allConfigs.first.name, 'Normal');
          },
        );

        test(
          'removeConfigs with failedTcp=true removes funnelStage 0 failures',
          () async {
            final manager = ConfigManager();
            await manager.clearAllData();

            await manager.addConfig(
              'vless://uuid@127.0.0.1:443?query=1#Fail',
              'Fail',
            );
            final failId = manager.allConfigs.first.id;

            // funnelStage is 0 by default. Set failure count.
            await manager.markFailure(failId);

            await manager.addConfig(
              'vless://uuid@127.0.0.1:443?query=1#Pass',
              'Pass',
            );
            final passId =
                manager.allConfigs.firstWhere((c) => c.name == 'Pass').id;

            // A config with failure, but funnelStage > 0 shouldn't be deleted by failedTcp
            await manager.markFailure(passId);
            final passConfig = manager.allConfigs
                .firstWhere((c) => c.name == 'Pass')
                .copyWith(funnelStage: 1);
            await manager.updateConfigDirectly(passConfig);

            expect(manager.allConfigs.length, 2);

            await manager.removeConfigs(failedTcp: true);

            expect(manager.allConfigs.length, 1);
            expect(manager.allConfigs.first.name, 'Pass');
          },
        );

        test(
          'removeConfigs with untestedSpeed=true removes funnelStage < 3',
          () async {
            final manager = ConfigManager();
            await manager.clearAllData();

            await manager.addConfig(
              'vless://uuid@127.0.0.1:443?query=1#Untested',
              'Untested',
            ); // stage 0
            await manager.addConfig(
              'vless://uuid@127.0.0.1:443?query=1#Tested',
              'Tested',
            );

            final testedConfig = manager.allConfigs
                .firstWhere((c) => c.name == 'Tested')
                .copyWith(funnelStage: 3);
            await manager.updateConfigDirectly(testedConfig);

            await manager.removeConfigs(untestedSpeed: true);

            expect(manager.allConfigs.length, 1);
            expect(manager.allConfigs.first.name, 'Tested');
          },
        );
      },
    );

    group('evaluateAutoSwitch thresholds', () {
      test(
        'evaluateAutoSwitch triggers on high ping when better options exist',
        () async {
          final manager = ConfigManager();
          await manager.clearAllData();
          manager.isAutoSwitchEnabled = true;
          manager.setConnected(true, status: 'Connected');

          await manager.addConfig(
            'vless://uuid@127.0.0.1:443?query=1#Good',
            'Good',
          );
          await manager.addConfig(
            'vless://uuid@127.0.0.1:443?query=1#Bad',
            'Bad',
          );

          final goodId =
              manager.allConfigs.firstWhere((c) => c.name == 'Good').id;
          final goodConfig = manager.allConfigs
              .firstWhere((c) => c.name == 'Good')
              .copyWith(funnelStage: 3);
          await manager.updateConfigDirectly(goodConfig);
          await manager.updateConfigMetrics(goodId, ping: 100);
          await manager.markSuccess(goodId); // To ensure it is validated

          final badConfig = manager.allConfigs.firstWhere(
            (c) => c.name == 'Bad',
          );
          manager.selectConfig(badConfig); // Initially on bad config

          // Wait for sorting/throttling to finish
          await Future.delayed(const Duration(milliseconds: 600));

          bool autoSwitchTriggered = false;
          manager.onAutoSwitch = (c) {
            autoSwitchTriggered = true;
          };

          // currentPing > 400 (panicThreshold), and (currentPing - bestPing) > 150 (improvementThreshold)
          // 500 - 100 = 400 > 150.
          await manager.evaluateAutoSwitch(500);

          expect(autoSwitchTriggered, isTrue);
          expect(manager.selectedConfig?.name, 'Good');
        },
      );

      test(
        'evaluateAutoSwitch ignores switch if AutoSwitch is disabled or disconnected',
        () async {
          final manager = ConfigManager();
          await manager.clearAllData();

          await manager.addConfig(
            'vless://uuid@127.0.0.1:443?query=1#Good',
            'Good',
          );
          final goodId = manager.allConfigs.first.id;
          await manager.markSuccess(goodId);
          await manager.updateConfigMetrics(goodId, ping: 100);

          bool autoSwitchTriggered = false;
          manager.onAutoSwitch = (c) {
            autoSwitchTriggered = true;
          };

          // Case 1: AutoSwitch disabled
          manager.isAutoSwitchEnabled = false;
          manager.setConnected(true, status: 'Connected');
          await manager.evaluateAutoSwitch(500);
          expect(autoSwitchTriggered, isFalse);

          // Case 2: AutoSwitch enabled but disconnected
          manager.isAutoSwitchEnabled = true;
          manager.setConnected(false, status: 'Disconnected');
          await manager.evaluateAutoSwitch(500);
          expect(autoSwitchTriggered, isFalse);
        },
      );
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
      // Since it's a true isolate compute, it takes time.
      final prefs = await SharedPreferences.getInstance();
      String? savedString;
      for (int i = 0; i < 200; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        await prefs.reload();
        savedString = prefs.getString('vpn_configs');
        if (savedString != null && savedString.length > 10000) break;
      }

      expect(savedString, isNotNull);
      expect(savedString!.length, greaterThan(10000));
    });
  });
}
