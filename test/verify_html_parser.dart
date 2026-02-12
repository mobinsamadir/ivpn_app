import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_manager.dart';

void main() {
  test('ConfigManager.parseMixedContent handles HTML entities and complex params', () async {
    const rawHtml = '''
      <!DOCTYPE html>
      <html>
        <head><title>Test Configs</title></head>
        <body>
          <p>Here is a config:</p>
          <a href="vless://uuid@domain:443?path=/ws&amp;host=domain&amp;security=tls#TestServer">Link</a>

          <p>Another with comma:</p>
          <code>vless://uuid2@domain:443?type=grpc,headerType=none&amp;serviceName=grpc#TestServer2</code>

          <p>And another with semicolon (common in shadowrocket params):</p>
          <div>
            vmess://eyJhZGQiOiIxMjcuMC4wLjEiLCJhaWQiOiIwIiwiYWxwbiI6IiIsImhvc3QiOiIiLCJpZCI6ImI4NGNiYmIxLWQ3MGQtNDc2ZS04NTYyLWQ2ZjdlN2IyM2JjNiIsIm5ldCI6InRjcCIsInBhdGgiOiIiLCJwb3J0IjoiNDQzIiwicHMiOiJUZXN0VHJvamFuIiwic2N5IjoiYXV0byIsInNubmkiOiIiLCJ0bHMiOiIiLCJ0eXBlIjoibm9uZSIsInYiOiIyIn0=
          </div>

          <p>And complex:</p>
          trojan://password@domain:443?security=tls&amp;type=tcp&amp;headerType=none#TestServer3

          <p>Invalid one:</p>
          http://google.com

          <p>Config in text with other stuff:</p>
          Check out ss://method:password@1.2.3.4:8888#Shadowsocks for access.
        </body>
      </html>
    ''';

    // Expected Output:
    // 1. vless://uuid@domain:443?path=/ws&host=domain&security=tls#TestServer
    // 2. vless://uuid2@domain:443?type=grpc,headerType=none&serviceName=grpc#TestServer2
    // 3. vmess://... (base64)
    // 4. trojan://password@domain:443?security=tls&type=tcp&headerType=none#TestServer3
    // 5. ss://method:password@1.2.3.4:8888#Shadowsocks

    final configs = await ConfigManager.parseMixedContent(rawHtml);

    // Debug print
    for (var c in configs) {
      print('Parsed: $c');
    }

    expect(configs, contains('vless://uuid@domain:443?path=/ws&host=domain&security=tls#TestServer'));
    expect(configs, contains('vless://uuid2@domain:443?type=grpc,headerType=none&serviceName=grpc#TestServer2'));
    expect(configs, contains('trojan://password@domain:443?security=tls&type=tcp&headerType=none#TestServer3'));
    expect(configs, contains('ss://method:password@1.2.3.4:8888#Shadowsocks'));

    // Check that &amp; is fully gone
    for (var config in configs) {
      expect(config.contains('&amp;'), isFalse, reason: 'Config should not contain HTML entity &amp;');
      expect(config.contains('<'), isFalse, reason: 'Config should not contain HTML tags');
      expect(config.contains('>'), isFalse, reason: 'Config should not contain HTML tags');
    }
  });

  test('ConfigManager.parseMixedContent handles raw text (non-HTML)', () async {
     const rawText = '''
vless://uuid@domain:443?path=/ws&host=domain&security=tls#RawServer
vmess://eyJhZGQiOiIxMjcuMC4wLjEiIn0=
     ''';

     final configs = await ConfigManager.parseMixedContent(rawText);
     expect(configs, contains('vless://uuid@domain:443?path=/ws&host=domain&security=tls#RawServer'));
     expect(configs, contains('vmess://eyJhZGQiOiIxMjcuMC4wLjEiIn0='));
  });
}
