
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

    test('Should fallback to standard VLESS when pbk is missing', () {
      // JSON missing pbk
      // {"add":"1.1.1.1","port":443,"id":"uuid","scy":"reality"}
      const base64Part = "eyJhZGQiOiIxLjEuMS4xIiwicG9ydCI6NDQzLCJpZCI6InV1aWQiLCJzY3kiOiJyZWFsaXR5In0=";
      const rawLink = "vless://$base64Part";

      final config = SingboxConfigGenerator.generateConfig(rawLink, listenPort: 10808, isTest: true);

      // Should contain server details
      expect(config.contains('"server":"1.1.1.1"'), isTrue);

      // Should NOT contain reality block (public_key)
      expect(config.contains('"public_key"'), isFalse);

      // Should contain tls enabled (since scy=reality implies tls fallback)
      expect(config.contains('"tls":{'), isTrue);
      expect(config.contains('"enabled":true'), isTrue);
    });

    test('Should handle VLESS URI with mixed casing and encoded characters', () {
      const uri = "vless://UUID@Example.Com:443?security=reality&pbk=ABC&sid=123#Tag";
      final config = SingboxConfigGenerator.generateConfig(uri, listenPort: 10808, isTest: true);

      expect(config.contains('"server":"Example.Com"'), isTrue);
      expect(config.contains('"public_key":"ABC"'), isTrue);
    });
  });
}
