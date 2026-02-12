import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_manager.dart';

void main() {
  test('ConfigManager.parseMixedContent handles HTML entities and complex params', () async {
    const rawHtml = '''
      <html>
        <body>
          <p>Here is a config:</p>
          <a href="vless://uuid@domain:443?path=/ws&amp;host=domain&amp;security=tls#TestServer">Link</a>
          <p>Another with comma:</p>
          vless://uuid2@domain:443?type=grpc,headerType=none&amp;serviceName=grpc#TestServer2
          <p>And another with semicolon (common in shadowrocket params):</p>
          vmess://eyJhZGQiOiIxMjcuMC4wLjEiLCJhaWQiOiIwIiwiYWxwbiI6IiIsImhvc3QiOiIiLCJpZCI6ImI4NGNiYmIxLWQ3MGQtNDc2ZS04NTYyLWQ2ZjdlN2IyM2JjNiIsIm5ldCI6InRjcCIsInBhdGgiOiIiLCJwb3J0IjoiNDQzIiwicHMiOiJUZXN0VHJvamFuIiwic2N5IjoiYXV0byIsInNubmkiOiIiLCJ0bHMiOiIiLCJ0eXBlIjoibm9uZSIsInYiOiIyIn0=
          <p>And complex:</p>
          trojan://password@domain:443?security=tls&amp;type=tcp&amp;headerType=none#TestServer3
        </body>
      </html>
    ''';

    // Expected Output:
    // 1. vless://uuid@domain:443?path=/ws&host=domain&security=tls#TestServer
    // 2. vless://uuid2@domain:443?type=grpc,headerType=none&serviceName=grpc#TestServer2
    // 3. vmess://eyJhZGQiOiIxMjcuMC4wLjEiLCJhaWQiOiIwIiwiYWxwbiI6IiIsImhvc3QiOiIiLCJpZCI6ImI4NGNiYmIxLWQ3MGQtNDc2ZS04NTYyLWQ2ZjdlN2IyM2JjNiIsIm5ldCI6InRjcCIsInBhdGgiOiIiLCJwb3J0IjoiNDQzIiwicHMiOiJUZXN0VHJvamFuIiwic2N5IjoiYXV0byIsInNubmkiOiIiLCJ0bHMiOiIiLCJ0eXBlIjoibm9uZSIsInYiOiIyIn0=
    // 4. trojan://password@domain:443?security=tls&type=tcp&headerType=none#TestServer3

    final configs = await ConfigManager.parseMixedContent(rawHtml);

    expect(configs, contains('vless://uuid@domain:443?path=/ws&host=domain&security=tls#TestServer'));
    expect(configs, contains('vless://uuid2@domain:443?type=grpc,headerType=none&serviceName=grpc#TestServer2'));
    expect(configs, contains('trojan://password@domain:443?security=tls&type=tcp&headerType=none#TestServer3'));

    // Check that &amp; is fully gone
    for (var config in configs) {
      expect(config.contains('&amp;'), isFalse, reason: 'Config should not contain HTML entity &amp;');
    }
  });
}
