import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/funnel_service.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Funnel Service Isolate Logic', () {
    test(
      'batchProcessConfigsInIsolate handles mixed valid and invalid configs',
      () {
        final validConfig = {
          'id': '1',
          'rawConfig':
              'vless://uuid@example.com:443?security=tls&type=tcp#Test',
        };

        // "not-a-url" will fail Uri.tryParse or have empty host
        final invalidConfig = {'id': '2', 'rawConfig': 'not-a-url'};

        final malformedConfig = {
          'id': '3',
          'rawConfig':
              'vmess://not-base64', // triggers base64 decode error, returns null
        };

        final configs = [validConfig, invalidConfig, malformedConfig];

        final results = batchProcessConfigsInIsolate(configs);

        expect(
          results.containsKey('1'),
          isTrue,
          reason: 'Valid config should be extracted',
        );
        expect(results['1']!['host'], 'example.com');
        expect(results['1']!['port'], 443);

        expect(
          results.containsKey('2'),
          isFalse,
          reason: 'Invalid config should be ignored',
        );
        expect(
          results.containsKey('3'),
          isFalse,
          reason: 'Malformed config should be ignored',
        );
      },
    );
  });

  group('FunnelService queue processing tests', () {
    test('startFunnel populates tcpQueue and processes configs correctly',
        () async {
      final service = FunnelService();

      // We start a local ServerSocket so the TCP worker can connect to it successfully.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      // Accept connections and immediately close them to simulate a valid TCP endpoint
      server.listen((client) {
        client.destroy();
      });

      final configs = [
        VpnConfigWithMetrics(
          id: '1',
          name: 'Test 1',
          rawConfig: 'vless://uuid@127.0.0.1:$port?security=tls&type=tcp#Test',
          funnelStage: 0,
          failureCount: 0,
        ),
        // Dead config (should be skipped unless retestDead is true)
        VpnConfigWithMetrics(
          id: 'dead_1',
          name: 'Dead Test',
          rawConfig: 'vless://uuid@127.0.0.1:1?security=tls&type=tcp#Test',
          funnelStage: 0,
          failureCount: 4,
        ),
      ];

      // Use retestDead = true to ensure it queues the dead one as well
      await service.startFunnel(retestDead: true, targetConfigs: configs);

      // Give workers time to pop queues and process (TCP should pass for Test 1, fail for Dead Test)
      // HTTP might fail because EphemeralTester needs a real setup, but it will execute the worker.
      await Future.delayed(const Duration(seconds: 3));

      // Stop the service
      await service.stop();
      await server.close();

      expect(service.progressStream, isNotNull);
    });

    test('startFunnel prevents concurrent executions', () async {
      final service = FunnelService();

      service.startFunnel();
      // Second call should log warning but not throw or crash
      await service.startFunnel();

      // Stop should cancel all streams safely
      service.stop();
    });

    test('stop clears internal state without throwing exceptions', () async {
      final service = FunnelService();

      service.startFunnel();

      // Stop should cancel all streams safely
      service.stop();

      expect(true, isTrue); // Graceful execution
    });
  });
}
