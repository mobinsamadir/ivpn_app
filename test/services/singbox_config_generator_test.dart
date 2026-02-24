import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/singbox_config_generator.dart';

void main() {
  group('SingboxConfigGenerator Tests', () {
    test('Correctly parses Reality config with "pbk" parameter', () {
      const rawLink = 'vless://uuid@example.com:443?security=reality&pbk=test_public_key&sid=test_sid&type=tcp&sni=example.com#RealityServer';
      final configJson = SingboxConfigGenerator.generateConfig(rawLink);
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
      const rawLink = 'vless://uuid@example.com:443?security=reality&public_key=test_public_key_alt&sid=test_sid&type=tcp&sni=example.com#RealityServer';
      final configJson = SingboxConfigGenerator.generateConfig(rawLink);
      final config = jsonDecode(configJson);

      final outbounds = config['outbounds'] as List;
      final proxy = outbounds.firstWhere((e) => e['tag'] == 'proxy');
      final tls = proxy['tls'];
      final reality = tls['reality'];

      expect(reality['enabled'], true);
      expect(reality['public_key'], 'test_public_key_alt');
    });

    test('Throws exception if both "pbk" and "public_key" are missing for Reality', () {
      const rawLink = 'vless://uuid@example.com:443?security=reality&sid=test_sid&type=tcp&sni=example.com#RealityServer';
      expect(
        () => SingboxConfigGenerator.generateConfig(rawLink),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Reality config missing public_key'))),
      );
    });
  });
}
