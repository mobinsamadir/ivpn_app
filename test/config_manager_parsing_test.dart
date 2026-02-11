import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_manager.dart';

void main() {
  test('parseMixedContent extracts and sanitizes configs correctly', () async {
    final input = '''
      Here is some text
      vless://uuid@example.com:443?security=tls#Test1
      Some noise
      vmess://ew0KICAidiI6ICIyIiwNCiAgInBzIjogIiIsDQogICJhZGQiOiAiMTI3LjAuMC4xIiwNCiAgInBvcnQiOiAiNDQzIiwNCiAgImlkIjogImJiYmJiYmJiLWJiYmItYmJiYi1iYmJiLWJiYmJiYmJiYmJiYiIsDQogICJhaWQiOiAiMCIsDQogICJuZXQiOiAidGNwIiwNCiAgInR5cGUiOiAibm9uZSIsDQogICJob3N0IjogIiIsDQogICJwYXRoIjogIiIsDQogICJ0bHMiOiAibm9uZSINCn0=
      More noise
      ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNzd29yZA==@example.com:443#SS
      trojan://password@example.com:443#Trojan

      Sanitization check:
      vless://clean?q=1.
      vless://clean?q=1,
      vless://clean?q=1)
      vless://clean?q=1?
      vless://clean?q=1.)
      vless://clean?q=1.,?
      vless://backtick`shouldstop
    ''';

    final results = await ConfigManager.parseMixedContent(input);

    expect(results, contains('vless://uuid@example.com:443?security=tls#Test1'));
    expect(results.any((s) => s.startsWith('vmess://')), isTrue);
    expect(results, contains('ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNzd29yZA==@example.com:443#SS'));
    expect(results, contains('trojan://password@example.com:443#Trojan'));

    // Sanitization verification
    // All sanitized versions should result in "vless://clean?q=1"
    // Since parseMixedContent dedups, we should see it once, and NOT see any dirty ones.
    expect(results, contains('vless://clean?q=1'));
    expect(results.any((s) => s.endsWith('.')), isFalse);
    expect(results.any((s) => s.endsWith(',')), isFalse);
    expect(results.any((s) => s.endsWith(')')), isFalse);
    expect(results.any((s) => s.endsWith('?')), isFalse);

    // Backtick check
    expect(results, contains('vless://backtick'));
  });

  test('parseMixedContent handles base64 decoded content', () async {
      // Input is base64 of "vless://hidden"
      final input = 'dmxlc3M6Ly9oaWRkZW4=';
      final results = await ConfigManager.parseMixedContent(input);
      expect(results, contains('vless://hidden'));
  });
}
