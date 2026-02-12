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

  test('ConfigManager.extractDriveConfirmationLink finds the link', () {
    const driveWarningHtml = '''
    <html>
      <body>
        <p>Google Drive - Virus scan warning</p>
        <p>This file is too large to scan.</p>
        <a href="/uc?export=download&confirm=t&id=12345">Download anyway</a>
        <a href="/other">Other link</a>
      </body>
    </html>
    ''';

    final link = ConfigManager.extractDriveConfirmationLink(driveWarningHtml);
    expect(link, equals('/uc?export=download&confirm=t&id=12345'));

    const driveWarningHtml2 = '''
    <html><body><a id="uc-download-link" href="/uc?export=download&confirm=X">Download</a></body></html>
    ''';
    final link2 = ConfigManager.extractDriveConfirmationLink(driveWarningHtml2);
    expect(link2, equals('/uc?export=download&confirm=X'));

    const noWarningHtml = '<html><body><p>Just text</p></body></html>';
    final link3 = ConfigManager.extractDriveConfirmationLink(noWarningHtml);
    expect(link3, isNull);
  });

  test('ConfigManager.parseMixedContent fixes base64 padding and removes junk', () async {
    // 1. Padding Fix Check
    // "eyJhZGQiOiIxMjcuMC4wLjEiIn0" (len 27, needs 1 '=')
    const brokenVmess = 'vmess://eyJhZGQiOiIxMjcuMC4wLjEiIn0';
    const expectedVmess = 'vmess://eyJhZGQiOiIxMjcuMC4wLjEiIn0=';

    // 2. Junk Removal Check
    // "vmess://...;&" -> "vmess://..."
    const junkVmess = 'vmess://eyJhZGQiOiIxMjcuMC4wLjEiIn0=;&';

    final configs = await ConfigManager.parseMixedContent('$brokenVmess\n$junkVmess');

    expect(configs, contains(expectedVmess));
    // The second one should also result in expectedVmess after cleaning junk
    // Note: ConfigManager uses a set, so duplicates are merged if identical.
    expect(configs.length, equals(1));
    expect(configs.first, equals(expectedVmess));

    // 3. Trojan Base64 Check
    // "trojan://eyJhZGQiOiIxMjcuMC4wLjEiIn0" (len 27) -> "trojan://eyJhZGQiOiIxMjcuMC4wLjEiIn0="
    const brokenTrojan = 'trojan://eyJhZGQiOiIxMjcuMC4wLjEiIn0';
    const expectedTrojan = 'trojan://eyJhZGQiOiIxMjcuMC4wLjEiIn0=';

    final configs2 = await ConfigManager.parseMixedContent(brokenTrojan);
    expect(configs2, contains(expectedTrojan));

    // 4. Trojan Standard (should NOT change)
    const standardTrojan = 'trojan://password@1.2.3.4:443';
    final configs3 = await ConfigManager.parseMixedContent(standardTrojan);
    expect(configs3, contains(standardTrojan));
  });
}
