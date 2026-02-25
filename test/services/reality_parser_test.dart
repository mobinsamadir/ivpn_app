
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/singbox_config_generator.dart';

void main() {
  group('Reality Parser Tests', () {
    test('Should parse standard VLESS URI with Reality correctly', () {
      const uri = "vless://uuid@example.com:443?security=reality&sni=example.com&fp=chrome&pbk=789&sid=123&type=tcp&headerType=none#Example";
      final config = SingboxConfigGenerator.generateConfig(uri, listenPort: 10808, isTest: true);

      // JSON Encode adds slashes, check substring presence
      expect(config.contains('"server":"example.com"'), isTrue);
      expect(config.contains('"server_port":443'), isTrue);
      expect(config.contains('"public_key":"789"'), isTrue);
      expect(config.contains('"short_id":"123"'), isTrue);
    });

    test('Should parse VLESS URI with missing pbk in query but present in Base64 JSON fallback', () {
      // Constructed malformed URI (vless://BASE64) simulating the failure case
      // JSON: {"add":"1.1.1.1","port":443,"id":"uuid","scy":"reality","sni":"example.com","pbk":"123456","sid":"short"}
      const base64Part = "eyJhZGQiOiIxLjEuMS4xIiwicG9ydCI6NDQzLCJpZCI6InV1aWQiLCJzY3kiOiJyZWFsaXR5Iiwic25pIjoiZXhhbXBsZS5jb20iLCJwYmsiOiIxMjM0NTYiLCJzaWQiOiJzaG9ydCJ9";
      const rawLink = "vless://$base64Part";

      final config = SingboxConfigGenerator.generateConfig(rawLink, listenPort: 10808, isTest: true);

      expect(config.contains('"server":"1.1.1.1"'), isTrue);
      expect(config.contains('"public_key":"123456"'), isTrue);
      expect(config.contains('"short_id":"short"'), isTrue);
    });

    test('Should throw error when pbk is completely missing', () {
      // JSON missing pbk
      // {"add":"1.1.1.1","port":443,"id":"uuid","scy":"reality"}
      const base64Part = "eyJhZGQiOiIxLjEuMS4xIiwicG9ydCI6NDQzLCJpZCI6InV1aWQiLCJzY3kiOiJyZWFsaXR5In0=";
      const rawLink = "vless://$base64Part";

      // Exception().toString() returns "Exception: message", so we check string matching
      expect(
        () => SingboxConfigGenerator.generateConfig(rawLink, listenPort: 10808, isTest: true),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Reality config missing public_key')))
      );
    });

    test('Should handle VLESS URI with mixed casing and encoded characters', () {
      const uri = "vless://UUID@Example.Com:443?security=reality&pbk=ABC&sid=123#Tag";
      final config = SingboxConfigGenerator.generateConfig(uri, listenPort: 10808, isTest: true);

      expect(config.contains('"server":"Example.Com"'), isTrue);
      expect(config.contains('"public_key":"ABC"'), isTrue);
    });
  });
}
