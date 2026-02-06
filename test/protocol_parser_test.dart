import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';

void main() {
  group('Universal Protocol Parser (Xray)', () {
    final vpnService = WindowsVpnService();

    test('VMess: Should parse correctly', () {
      // {"add":"1.2.3.4","port":"443","id":"uuid","net":"ws","tls":"tls","v":"2"}
      const String sampleVmess = "vmess://eyJhZGQiOiIxLjIuMy40IiwicG9ydCI6IjQ0MyIsImlkIjoidXVpZCIsIm5ldCI6IndzIiwidGxzIjoidGxzIiwidiI6IjIifQ==";
      final String configJson = vpnService.generateConfig(sampleVmess);
      final Map<String, dynamic> config = jsonDecode(configJson);

      expect(config['outbounds'][0]['protocol'], equals('vmess'));
      expect(config['outbounds'][0]['settings']['vnext'][0]['address'], equals('1.2.3.4'));
      expect(config['outbounds'][0]['streamSettings']['network'], equals('ws'));
    });

    test('VLESS Reality: Should parse correctly', () {
      const String sampleVless = "vless://my-uuid@8.8.8.8:443?type=grpc&security=reality&sni=google.com&pbk=my-pub-key&sid=my-sid#MyServer";
      final String configJson = vpnService.generateConfig(sampleVless);
      final Map<String, dynamic> config = jsonDecode(configJson);

      final outbound = config['outbounds'][0];
      expect(outbound['protocol'], equals('vless'));
      expect(outbound['settings']['vnext'][0]['users'][0]['id'], equals('my-uuid'));
      
      final stream = outbound['streamSettings'];
      expect(stream['network'], equals('grpc'));
      expect(stream['security'], equals('reality'));
      expect(stream['realitySettings']['serverName'], equals('google.com'));
      expect(stream['realitySettings']['publicKey'], equals('my-pub-key'));
    });

    test('Trojan: Should parse correctly', () {
      const String sampleTrojan = "trojan://my-password@1.1.1.1:443?security=tls&sni=example.com#TrojanServer";
      final String configJson = vpnService.generateConfig(sampleTrojan);
      final Map<String, dynamic> config = jsonDecode(configJson);

      final outbound = config['outbounds'][0];
      expect(outbound['protocol'], equals('trojan'));
      expect(outbound['settings']['servers'][0]['password'], equals('my-password'));
      expect(outbound['streamSettings']['security'], equals('tls'));
    });

    test('Shadowsocks: Should parse URI format correctly', () {
      // ss://method:pass@host:port
      final String auth = base64Encode(utf8.encode("aes-256-gcm:pass123"));
      final String sampleSS = "ss://$auth@8.8.4.4:8080#SS-Tag";
      
      final String configJson = vpnService.generateConfig(sampleSS);
      final Map<String, dynamic> config = jsonDecode(configJson);

      final outbound = config['outbounds'][0];
      expect(outbound['protocol'], equals('shadowsocks'));
      expect(outbound['settings']['servers'][0]['method'], equals('aes-256-gcm'));
      expect(outbound['settings']['servers'][0]['address'], equals('8.8.4.4'));
    });

    test('Parser should be case-insensitive to protocol', () {
       const String vmessUpper = "VMESS://eyJhZGQiOiIxLjIuMy40IiwicG9ydCI6IjQ0MyIsImlkIjoidXVpZCIsIm5ldCI6IndzIiwidGxzIjoidGxzIiwidiI6IjIifQ==";
       expect(() => vpnService.generateConfig(vmessUpper), returnsNormally);
    });

    test('Parser should throw for unsupported protocols', () {
       expect(() => vpnService.generateConfig("unknown://..."), throwsException);
    });
  });
}
