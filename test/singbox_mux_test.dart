import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/singbox_config_generator.dart';

void main() {
  test('SingboxConfigGenerator adds Mux to VLESS, VMESS, and TROJAN', () {
    // 1. VLESS
    const vlessLink = "vless://uuid@example.com:443?security=tls&type=tcp#VLESS";
    final vlessJson = SingboxConfigGenerator.generateConfig(vlessLink);
    final vlessConfig = jsonDecode(vlessJson);
    final vlessOutbound = vlessConfig['outbounds'][0];

    expect(vlessOutbound['type'], 'vless');
    expect(vlessOutbound['multiplex'], isNotNull, reason: 'VLESS missing multiplex');
    expect(vlessOutbound['multiplex']['enabled'], true);
    expect(vlessOutbound['multiplex']['padding'], true);
    expect(vlessOutbound['multiplex']['brutal'], true);

    // 2. VMESS
    final vmessMap = {
      "v": "2", "ps": "VMESS", "add": "example.com", "port": 443, "id": "uuid",
      "aid": 0, "net": "tcp", "type": "none", "host": "", "path": "", "tls": "tls"
    };
    final vmessLink = "vmess://${base64Encode(utf8.encode(jsonEncode(vmessMap)))}";
    final vmessJson = SingboxConfigGenerator.generateConfig(vmessLink);
    final vmessConfig = jsonDecode(vmessJson);
    final vmessOutbound = vmessConfig['outbounds'][0];

    expect(vmessOutbound['type'], 'vmess');
    expect(vmessOutbound['multiplex'], isNotNull, reason: 'VMESS missing multiplex');
    expect(vmessOutbound['multiplex']['enabled'], true);

    // 3. TROJAN
    const trojanLink = "trojan://password@example.com:443?security=tls&type=tcp#TROJAN";
    final trojanJson = SingboxConfigGenerator.generateConfig(trojanLink);
    final trojanConfig = jsonDecode(trojanJson);
    final trojanOutbound = trojanConfig['outbounds'][0];

    expect(trojanOutbound['type'], 'trojan');
    expect(trojanOutbound['multiplex'], isNotNull, reason: 'TROJAN missing multiplex');
    expect(trojanOutbound['multiplex']['enabled'], true);

    // 4. SHADOWSOCKS (Should NOT have Mux - assuming, or checking if it wasn't added unintentionally)
    // The requirement was specific to vless/vmess/trojan.
    const ssLink = "ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNzd29yZA==@example.com:443#SS";
    final ssJson = SingboxConfigGenerator.generateConfig(ssLink);
    final ssConfig = jsonDecode(ssJson);
    final ssOutbound = ssConfig['outbounds'][0];

    expect(ssOutbound['type'], 'shadowsocks');
    expect(ssOutbound.containsKey('multiplex'), isFalse, reason: 'Shadowsocks should NOT have multiplex');

    print('✅ Singbox Mux Verification Passed!');
  });
}
