import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/funnel_service.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';

void main() {
  group('Funnel Service Isolate Logic', () {
    test('batchProcessConfigsInIsolate handles mixed valid and invalid configs', () {
      final validConfig = VpnConfigWithMetrics(
        id: '1',
        rawConfig: 'vless://uuid@example.com:443?security=tls&type=tcp#Test',
        name: 'Test',
        addedDate: DateTime.now(),
      );

      // "not-a-url" will fail Uri.tryParse or have empty host
      final invalidConfig = VpnConfigWithMetrics(
        id: '2',
        rawConfig: 'not-a-url',
        name: 'Invalid',
        addedDate: DateTime.now(),
      );

      final malformedConfig = VpnConfigWithMetrics(
        id: '3',
        rawConfig: 'vmess://not-base64', // triggers base64 decode error, returns null
        name: 'Malformed',
        addedDate: DateTime.now(),
      );

      final configs = [validConfig, invalidConfig, malformedConfig];

      final results = batchProcessConfigsInIsolate(configs);

      expect(results.containsKey('1'), isTrue, reason: 'Valid config should be extracted');
      expect(results['1']!['host'], 'example.com');
      expect(results['1']!['port'], 443);

      expect(results.containsKey('2'), isFalse, reason: 'Invalid config should be ignored');
      expect(results.containsKey('3'), isFalse, reason: 'Malformed config should be ignored');
    });
  });
}
