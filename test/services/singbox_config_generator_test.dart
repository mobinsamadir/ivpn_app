import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/singbox_config_generator.dart';

void main() {
  group('SingboxConfigGenerator Tests', () {
    test('Correctly parses Reality config with "pbk" parameter', () {
      const rawLink =
          'vless://uuid@example.com:443?security=reality&pbk=test_public_key&sid=test_sid&type=tcp&sni=example.com#RealityServer';
      final configJson = SingboxConfigGenerator.generateConfig(
        rawLink,
        listenPort: 10808,
      );
      final config = jsonDecode(configJson);

      final outbounds = config['outbounds'] as List;
      final proxy = outbounds.firstWhere((e) => e['tag'] == 'proxy');
      final tls = proxy['tls'];
      final reality = tls['reality'];

      expect(reality['enabled'], true);
      expect(reality['public_key'], 'test_public_key');
      expect(reality['short_id'], 'test_sid');
    });

    test('Correctly parses Reality config with "public_key" parameter', () {
      const rawLink =
          'vless://uuid@example.com:443?security=reality&public_key=test_public_key_alt&sid=test_sid&type=tcp&sni=example.com#RealityServer';
      final configJson = SingboxConfigGenerator.generateConfig(
        rawLink,
        listenPort: 10808,
      );
      final config = jsonDecode(configJson);

      final outbounds = config['outbounds'] as List;
      final proxy = outbounds.firstWhere((e) => e['tag'] == 'proxy');
      final tls = proxy['tls'];
      final reality = tls['reality'];

      expect(reality['enabled'], true);
      expect(reality['public_key'], 'test_public_key_alt');
    });

    test(
      'Falls back to standard TLS if both "pbk" and "public_key" are missing for Reality',
      () {
        const rawLink =
            'vless://uuid@example.com:443?security=reality&sid=test_sid&type=tcp&sni=example.com#RealityServer';

        final configJson = SingboxConfigGenerator.generateConfig(
          rawLink,
          listenPort: 10808,
        );
        final config = jsonDecode(configJson);

        final outbounds = config['outbounds'] as List;
        final proxy = outbounds.firstWhere((e) => e['tag'] == 'proxy');
        final tls = proxy['tls'];

        // Should have TLS enabled
        expect(tls['enabled'], true);
        expect(tls['server_name'], 'example.com');

        // Should NOT have reality block
        expect(tls.containsKey('reality'), false);
      },
    );

    test('Injects strict_route (Kill Switch) based on flag', () {
      const rawLink =
          'vless://uuid@example.com:443?security=none&type=tcp#Test';

      // Test when enabled
      final configJsonEnabled = SingboxConfigGenerator.generateConfig(
        rawLink,
        listenPort: 10808,
        isKillSwitchEnabled: true,
      );
      final configEnabled = jsonDecode(configJsonEnabled);
      final inboundsEnabled = configEnabled['inbounds'] as List;
      final tunInboundEnabled = inboundsEnabled.firstWhere(
        (e) => e['type'] == 'tun',
      );
      expect(tunInboundEnabled['strict_route'], isTrue);

      // Test when disabled
      final configJsonDisabled = SingboxConfigGenerator.generateConfig(
        rawLink,
        listenPort: 10808,
        isKillSwitchEnabled: false,
      );
      final configDisabled = jsonDecode(configJsonDisabled);
      final inboundsDisabled = configDisabled['inbounds'] as List;
      final tunInboundDisabled = inboundsDisabled.firstWhere(
        (e) => e['type'] == 'tun',
      );
      expect(tunInboundDisabled['strict_route'], isFalse);
    });

    test(
      'Injects split tunneling routing rules when packages are provided',
      () {
        const rawLink =
            'vless://uuid@example.com:443?security=none&type=tcp#Test';
        final bypassedPackages = ['com.example.app1', 'com.example.app2'];

        final configJson = SingboxConfigGenerator.generateConfig(
          rawLink,
          listenPort: 10808,
          splitTunnelingPackages: bypassedPackages,
        );
        final config = jsonDecode(configJson);

        final route = config['route'];
        final rules = route['rules'] as List;

        final splitTunnelRule = rules.firstWhere(
          (rule) => rule['package_name'] != null,
          orElse: () => null,
        );

        expect(
          splitTunnelRule,
          isNotNull,
          reason: 'Split tunneling rule should exist',
        );
        expect(splitTunnelRule['package_name'], equals(bypassedPackages));
        expect(splitTunnelRule['outbound'], equals('direct'));
      },
    );

    test(
      'Does not inject split tunneling rule when packages list is empty',
      () {
        const rawLink =
            'vless://uuid@example.com:443?security=none&type=tcp#Test';

        final configJson = SingboxConfigGenerator.generateConfig(
          rawLink,
          listenPort: 10808,
          splitTunnelingPackages: [],
        );
        final config = jsonDecode(configJson);

        final route = config['route'];
        final rules = route['rules'] as List;

        final splitTunnelRule = rules.firstWhere(
          (rule) => rule['package_name'] != null,
          orElse: () => null,
        );

        expect(
          splitTunnelRule,
          isNull,
          reason: 'Split tunneling rule should NOT exist when list is empty',
        );
      },
    );
  });
}
