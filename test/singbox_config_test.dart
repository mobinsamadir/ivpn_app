
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/singbox_config_generator.dart';
import 'dart:io';
import 'package:ivpn_new/services/native_vpn_service.dart';
import 'package:ivpn_new/services/config_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // Enable real network requests
  
  group('SingboxConfigGenerator Tests', () {
    test('Should generate valid VLESS config', () {
      const vlessLink = "vless://uuid@example.com:443?security=tls&type=tcp&flow=xtls-rprx-vision#Example";
      final jsonString = SingboxConfigGenerator.generateConfig(vlessLink);
      
      final Map<String, dynamic> config = jsonDecode(jsonString);
      
      expect(config['inbounds'], isNotEmpty);
      expect(config['outbounds'], isNotEmpty);
      expect(config['route'], isNotNull);
      
      final outbound = config['outbounds'][0];
      expect(outbound['type'], equals('vless'));
      expect(outbound['server'], equals('example.com'));
      expect(outbound['server_port'], equals(443));
      expect(outbound['uuid'], equals('uuid'));
      expect(outbound['flow'], equals('xtls-rprx-vision'));
    });

    test('Should generate valid VMess config', () {
      final vmessJson = jsonEncode({
        "v": "2",
        "ps": "VMess Test",
        "add": "vmess.example.com",
        "port": 10086,
        "id": "a348-2342-2342-2342",
        "aid": 0,
        "net": "ws",
        "type": "none",
        "host": "host.com",
        "path": "/path",
        "tls": "tls"
      });
      final vmessLink = "vmess://${base64Encode(utf8.encode(vmessJson))}";
      
      final jsonString = SingboxConfigGenerator.generateConfig(vmessLink);
      final config = jsonDecode(jsonString);
      
      final outbound = config['outbounds'][0];
      expect(outbound['type'], equals('vmess'));
      expect(outbound['server'], equals('vmess.example.com'));
      expect(outbound['transport']['type'], equals('ws'));
      expect(outbound['tls']['enabled'], isTrue);
    }, timeout: const Timeout(Duration(seconds: 2)));
  });

  group('MethodChannel Integration', () {
    const MethodChannel channel = MethodChannel('com.example.ivpn_new/method');
    final List<MethodCall> log = <MethodCall>[];

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        log.add(methodCall);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      log.clear();
    });

    test('connect() should Invoke MethodChannel with Config', () async {
      const vlessLink = "vless://uuid@example.com:443?security=tls&type=tcp#Example";
      
      final service = NativeVpnService(); 
      await service.connect(vlessLink);

      expect(log, hasLength(1));
      expect(log.first.method, 'connect');
      expect(log.first.arguments, isMap);
      expect(log.first.arguments['config'], isNotEmpty);
      
      final config = jsonDecode(log.first.arguments['config']);
      expect(config['inbounds'], isNotEmpty);
    });
  });

  group('Real World & Binary Validation', () {
    // Hardcoded Real Configs
    final realConfigs = [
      "ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpWVmxBZmY3N0NuQVU0M0FvYzVqMTVZ@90.156.203.62:5112#%40V2ray_confs",
      "vless://29187857-4a1f-4d1e-88eb-0016771e0dbb@162.159.152.53:443?path=%2F%3Fed%3D2560---PLANB_NET---Join---PLANB_NET---Join---PLANB_NET---Join---PLANB_NET&security=tls&alpn=h3&encryption=none&host=vless.hubp.de&fp=random&type=ws&sni=vless.hubp.de#%2540IRAN_V2RAY1",
      "ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpKSWhONnJCS2thRWJvTE5YVlN2NXJx@142.4.216.225:80#All-%40IRAN_V2RAY1",
      "ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpvWklvQTY5UTh5aGNRVjhrYTNQYTNB@45.87.175.69:8080#%40IRAN_V2RAY1",
      "vmess://eyJhZGQiOiI4NS4xOTUuMTAxLjEyMiIsImFpZCI6IjAiLCJhbHBuIjoiIiwiZnAiOiIiLCJob3N0IjoiIiwiaWQiOiJmM2Q0MTY3ZS1iMTVlLTRlNDYtODJlOS05Mjg2ZWY5M2ZkYTciLCJuZXQiOiJ0Y3AiLCJwYXRoIjoiIiwicG9ydCI6IjQwODc4IiwicHMiOiJJUi1ASVJBTl9WMlJBWTEiLCJzY3kiOiJhdXRvIiwic25pIjoiIiwidGxzIjoiIiwidHlwZSI6Im5vbmUiLCJ2IjoiMiJ9"
    ];

    test('Batch Binary Dry-Run on Real Configs', () async {
      for (final link in realConfigs) {
        print("Testing Link: ${link.substring(0, 20)}...");
        final jsonString = SingboxConfigGenerator.generateConfig(link);
        final config = jsonDecode(jsonString);
        expect(config['outbounds'].first['server'], isNotEmpty);
        await _runBinaryCheck(jsonString);
      }
    });

    test('Subscription Fetch & Stress Test', () async {
      const subUrl = "https://raw.githubusercontent.com/mamadz13/-IRAN_V2RAY1-IRAN_V2RAY1/refs/heads/main/@iran_v2ray1.txt";
      final links = await ConfigImporter.fetchAndParse(subUrl);
      
      expect(links, isNotEmpty);
      print("Found ${links.length} configs in subscription. Running binary check on ALL...");
      
      int passed = 0;
      for (final link in links) {
        try {
          final jsonString = SingboxConfigGenerator.generateConfig(link);
          await _runBinaryCheck(jsonString);
          passed++;
        } catch (e) {
          print("⚠️ Failed config: ${link.substring(0, min(50, link.length))}\nError: $e");
        }
      }
      print("Batch Result: $passed/${links.length} passed binary check.");
      expect(passed, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}

// Helper for Binary Check
Future<void> _runBinaryCheck(String jsonContent) async {
  if (!Platform.isWindows) return;

  // Use absolute path to ensure shell compatibility
  final binPath = "${Directory.current.path}\\assets\\executables\\windows\\sing-box.exe";
  
  if (!File(binPath).existsSync()) {
    print("⚠️ Skipping binary check: sing-box.exe not found at $binPath");
    return;
  }

  final tempDir = Directory.systemTemp.createTempSync("singbox_check_");
  final configFile = File("${tempDir.path}/check.json");
  await configFile.writeAsString(jsonContent);

  final result = await Process.run(
    binPath, 
    ['check', '-c', configFile.path, '-D', '.'],
    runInShell: true
  );

  if (result.exitCode != 0) {
    throw Exception("Binary Check Failed!\nSTDERR: ${result.stderr}\nConfig: $jsonContent");
  }
  
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
}

int min(int a, int b) => a < b ? a : b;
