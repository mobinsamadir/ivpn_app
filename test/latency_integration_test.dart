
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/latency_service.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';
import 'package:ivpn_new/utils/file_logger.dart';

void main() {
  // FIX: Initialize binding FIRST
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Initialize logger with mock
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (message) async {
        return null;
      });

  // Configs to test (Real Examples)
  // Configs to test (Real Verified Examples)
  final List<String> testConfigs = [
    // 1. VMess
    "vmess://eyJhZGQiOiI4NS4xOTUuMTAxLjEyMiIsImFpZCI6IjAiLCJhbHBuIjoiIiwiZnAiOiIiLCJob3N0IjoiIiwiaWQiOiJmM2Q0MTY3ZS1iMTVlLTRlNDYtODJlOS05Mjg2ZWY5M2ZkYTciLCJuZXQiOiJ0Y3AiLCJwYXRoIjoiIiwicG9ydCI6IjQwODc4IiwicHMiOiJJUi1ASVJBTl9WMlJBWTEiLCJzY3kiOiJhdXRvIiwic25pIjoiIiwidGxzIjoiIiwidHlwZSI6Im5vbmUiLCJ2IjoiMiJ9",
    // 2. Shadowsocks
    "ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpKSWhONnJCS2thRWJvTE5YVlN2NXJx@142.4.216.225:80#All-%40IRAN_V2RAY1",
    // 3. VLESS
    "vless://29187857-4a1f-4d1e-88eb-0016771e0dbb@162.159.152.53:443?path=%2F%3Fed%3D2560---PLANB_NET---Join---PLANB_NET---Join---PLANB_NET---Join---PLANB_NET&security=tls&alpn=h3&encryption=none&host=vless.hubp.de&fp=random&type=ws&sni=vless.hubp.de#%2540IRAN_V2RAY1",
  ];

  late LatencyService latencyService;
  late WindowsVpnService vpnService;

  setUp(() {
    // Ensure we can log
    FileLogger.init();
    vpnService = WindowsVpnService();
    latencyService = LatencyService(vpnService);
  });

  print('\n🚀 STARTING AUTONOMOUS LATENCY TEST (Slow-Run)');
  print('-----------------------------------------');

  for (int i = 0; i < testConfigs.length; i++) {
    test('Config #$i Check (With Retry)', () async {
       final config = testConfigs[i].trim();
       print('\n[Test $i] Pinging Config...');
       print('--- Core Logs for this config ---');

       int latency = -1;
       
       // TRY 1
       print("   > Attempt 1...");
       final sw = Stopwatch()..start();
       latency = await latencyService.getLatency(config);
       sw.stop();
       
       // RETRY LOGIC
       if (latency == -1) {
          print("   ⚠️ Attempt 1 Failed. Retrying in 3s...");
          await Future.delayed(const Duration(seconds: 3));
          
          print("   > Attempt 2 (Retry)...");
          latency = await latencyService.getLatency(config);
       }

       print('   > Final Result: $latency ms');

       if (latency == -1) {
           print('   ❌ TEST FAILED: Config Dead after 2 attempts.');
       } else {
           print('   ✅ Config ALIVE.');
       }
       
       // Strict Assertion
       expect(latency, isNot(-1));
    });
  }
}
