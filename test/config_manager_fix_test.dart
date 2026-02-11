import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ConfigManager Fixes Verification', () async {
    print('--- Testing ConfigManager Fixes ---');

    // 1. Mock HTML content with embedded configs and LINKS (that should NOT be followed)
    final mockHtml = '''
<!DOCTYPE html>
<html>
<body>
  <h1>My Vless Configs</h1>
  <p>Here is a config:</p>
  <code>vless://uuid@example.com:443?security=tls#TestConfig1</code>

  <p>Another one:</p>
  <code>vmess://eyJhZGQiOiJleGFtcGxlLmNvbSIsIm5ldCI6InRjcCJ9</code>

  <a href="https://drive.google.com/some-folder">Check this folder</a>
  <a href="https://mysite.com/sub">Subscription Link</a>
</body>
</html>
    ''';

    print('Input Length: ${mockHtml.length}');

    // 2. Run parseMixedContent
    // Note: We can't easily mock the http.get calls inside ConfigManager if we didn't inject a client,
    // but since we removed the recursion, there SHOULD BE NO http.get calls.
    // If there WERE recursion, the script would fail or try to fetch 'https://drive.google.com...'

    final configs = await ConfigManager.parseMixedContent(mockHtml);

    print('Extracted Configs: ${configs.length}');
    for (var c in configs) {
      print(' - $c');
    }

    expect(configs.length, 2, reason: 'Expected 2 configs (vless + vmess)');
    expect(configs.any((c) => c.contains('vless://')), isTrue, reason: 'Missing vless config');
    expect(configs.any((c) => c.contains('vmess://')), isTrue, reason: 'Missing vmess config');

    // 3. Test Base64 decoding logic
    final base64Content = base64Encode(utf8.encode('vless://uuid@example.com:443?security=tls#Base64Config'));
    final base64Configs = await ConfigManager.parseMixedContent(base64Content);

    expect(base64Configs.length, 1, reason: 'Base64 decoding failed');
    expect(base64Configs.first.contains('Base64Config'), isTrue);

    print('✅ ConfigManager Fix Verification Passed!');
  });
}
