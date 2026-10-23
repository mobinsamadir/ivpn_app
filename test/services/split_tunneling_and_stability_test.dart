import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/models/app_info.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';

void main() {
  group('Split Tunneling & InstalledApp Tests', () {
    test('Correctly detects Iranian apps by package name and keywords', () {
      final snapp = InstalledApp(
        name: 'Snapp',
        packageName: 'cab.snapp.passenger',
        isSystemApp: false,
      );
      final digikala = InstalledApp(
        name: 'Digikala',
        packageName: 'com.digikala.app',
        isSystemApp: false,
      );
      final mellat = InstalledApp(
        name: 'Hamrah Bank Mellat',
        packageName: 'ir.mellat.mobile',
        isSystemApp: false,
      );
      final telegram = InstalledApp(
        name: 'Telegram',
        packageName: 'org.telegram.messenger',
        isSystemApp: false,
      );

      expect(snapp.isIranianApp, isTrue);
      expect(digikala.isIranianApp, isTrue);
      expect(mellat.isIranianApp, isTrue);
      expect(telegram.isIranianApp, isFalse);
    });

    test('Parses from Map with base64 icon cleanly', () {
      final app = InstalledApp.fromMap({
        'name': 'Test App',
        'packageName': 'com.test.app',
        'isSystemApp': true,
        'icon': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      });

      expect(app.name, equals('Test App'));
      expect(app.packageName, equals('com.test.app'));
      expect(app.isSystemApp, isTrue);
      expect(app.iconBytes, isNotNull);
      expect(app.iconBytes!.isNotEmpty, isTrue);
    });
  });

  group('Stability Index & Ranking Tests', () {
    test('Calculates stability index taking jitter into account', () {
      // Config A: Low jitter (TCP 100ms, HTTP 115ms => Jitter 15ms)
      final configStable = VpnConfigWithMetrics(
        id: 'stable_1',
        name: 'Stable Server',
        rawConfig: 'vless://example@1.1.1.1:443?security=reality',
        ping: 100,
        funnelStage: 2,
        stageResults: {
          'TCP': TestResult(success: true, latency: 100),
          'HTTP': TestResult(success: true, latency: 115),
        },
      );

      // Config B: High jitter / unstable (TCP 60ms, HTTP 420ms => Jitter 360ms)
      final configJittery = VpnConfigWithMetrics(
        id: 'jittery_1',
        name: 'Jittery Server',
        rawConfig: 'vless://example@2.2.2.2:443?security=reality',
        ping: 60,
        funnelStage: 2,
        stageResults: {
          'TCP': TestResult(success: true, latency: 60),
          'HTTP': TestResult(success: true, latency: 420),
        },
      );

      expect(configStable.stabilityIndex, greaterThan(configJittery.stabilityIndex));
      expect(configStable.stabilityIndex, greaterThanOrEqualTo(90));
      expect(configJittery.stabilityIndex, lessThanOrEqualTo(75));
    });

    test('Prioritizes highly stable server over erratic instant ping in comparison', () {
      // Server 1: 110ms with 98% stability
      final serverStable = VpnConfigWithMetrics(
        id: 's1',
        name: 'Stable',
        rawConfig: 'vless://example@1.1.1.1:443?security=reality',
        ping: 110,
        funnelStage: 2,
        stageResults: {
          'TCP': TestResult(success: true, latency: 110),
          'HTTP': TestResult(success: true, latency: 120),
        },
      );

      // Server 2: 70ms with high failure count and jitter
      final serverErratic = VpnConfigWithMetrics(
        id: 's2',
        name: 'Erratic',
        rawConfig: 'vless://example@2.2.2.2:443?security=reality',
        ping: 70,
        funnelStage: 2,
        failureCount: 2,
        stageResults: {
          'TCP': TestResult(success: true, latency: 70),
          'HTTP': TestResult(success: true, latency: 350),
        },
      );

      // In compareTo: smaller is ranked first
      final comparison = serverStable.compareTo(serverErratic);
      expect(comparison, lessThan(0), reason: 'Stable server should rank ahead of erratic server');
    });
  });
}
