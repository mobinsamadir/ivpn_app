import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_parser.dart';

void main() {
  group('ConfigParser Tests', () {
    test('Parses raw config links directly', () async {
      const input = '''
vmess://eyJhZGQiOiIxLjEuMS4xIn0=
vless://uuid@1.1.1.1:443
''';
      final results = await parseConfigsInIsolate(input);
      expect(results, hasLength(2));
      expect(results[0], 'vmess://eyJhZGQiOiIxLjEuMS4xIn0=');
      expect(results[1], 'vless://uuid@1.1.1.1:443');
    });

    test('Decodes Base64 encoded configs', () async {
      const raw = 'vmess://eyJhZGQiOiIxLjEuMS4xIn0=\nvless://uuid@1.1.1.1:443';
      final encoded = base64Encode(utf8.encode(raw));

      final results = await parseConfigsInIsolate(encoded);
      expect(results, hasLength(2));
      expect(results[0], 'vmess://eyJhZGQiOiIxLjEuMS4xIn0=');
    });

    test('Extracts configs from HTML body', () async {
      const html = '''
<!DOCTYPE html>
<html>
<body>
  <p>Here are some servers:</p>
  vmess://server1
  <div>
    vless://server2
  </div>
</body>
</html>
''';
      final results = await parseConfigsInIsolate(html);
      expect(results, hasLength(2));
      expect(results, contains('vmess://server1'));
      expect(results, contains('vless://server2'));
    });

    test('Extracts configs from HTML anchor tags', () async {
      const html = '''
<html>
<body>
  <a href="vmess://link1">Link 1</a>
  <a href="trojan://link2">Link 2</a>
</body>
</html>
''';
      final results = await parseConfigsInIsolate(html);
      expect(results, hasLength(2));
      expect(results, contains('vmess://link1'));
      expect(results, contains('trojan://link2'));
    });

    test('Handles mixed content and sanitizes trailing characters', () async {
      const text = '''
Check this out: vmess://config1, and this one: vless://config2.
Also trojan://config3;
''';
      final results = await parseConfigsInIsolate(text);
      expect(results, hasLength(3));
      expect(results[0], 'vmess://config1');
      expect(results[1], 'vless://config2');
      expect(results[2], 'trojan://config3');
    });

    test('Handles URL encoded content', () async {
      // vmess://%7B%22add%22%3A%221.1.1.1%22%7D -> vmess://{"add":"1.1.1.1"}
      const input = 'vmess://%7B%22add%22%3A%221.1.1.1%22%7D';
      final results = await parseConfigsInIsolate(input);

      expect(results, hasLength(1));
      expect(results.first, 'vmess://{"add":"1.1.1.1"}');
    });

    test('Returns empty list for garbage input', () async {
      const input = 'Just some random text without any protocols.';
      final results = await parseConfigsInIsolate(input);
      expect(results, isEmpty);
    });

    test('HTML parser works on messy but valid-ish HTML', () async {
      // Input that triggers HTML path but has config in body text
      const input = '<div class="messy"> vmess://valid_config </div>';

      final results = await parseConfigsInIsolate(input);
      expect(results, contains('vmess://valid_config'));
    });
  });
}
