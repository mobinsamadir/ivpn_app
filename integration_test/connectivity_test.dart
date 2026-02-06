import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ivpn_new/services/latency_service.dart';
import 'package:ivpn_new/utils/advanced_logger.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';
import 'dart:io';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('🔥 Automated Connectivity Test (Ground Truth) 🔥', (WidgetTester tester) async {
    // We need to initialize the service with satisfy its dependency
    final vpnService = WindowsVpnService();
    final service = LatencyService(vpnService);
    
    // The "Golden" Configs provided by user
    final configs = [
      {
        'type': 'Shadowsocks',
        'uri': 'ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpWVmxBZmY3N0NuQVU0M0FvYzVqMTVZ@90.156.203.62:5112#%40V2ray_confs'
      },
      {
        'type': 'VMess',
        'uri': 'vmess://ew0KICAidiI6ICIyIiwNCiAgInBzIjogIklSLUBJUkFOX1YyUkFZMSIsDQogICJhZGQiOiAiODUuMTk1LjEwMS4xMjIiLA0KICAicG9ydCI6ICI0MDg3OCIsDQogICJpZCI6ICJmM2Q0MTY3ZS1iMTVlLTRlNDYtODJlOS05Mjg2ZWY5M2ZkYTciLA0KICAiYWlkIjogIjAiLA0KICAic2N5IjogImF1dG8iLA0KICAibmV0IjogInRjcCIsDQogICJ0eXBlIjogIm5vbmUiLA0KICAiaG9zdCI6ICIiLA0KICAicGF0aCI6ICIiLA0KICAidGxzIjogIiIsDQogICJzbmkiOiAiIiwNCiAgImFscG4iOiAiIg0KfQ=='
      },
      {
        'type': 'VLESS (Cloudflare)',
        'uri': 'vless://29187857-4a1f-4d1e-88eb-0016771e0dbb@162.159.152.53:443?encryption=none&security=tls&sni=vless.hubp.de&alpn=h3&type=ws&host=vless.hubp.de&path=%2F%3Fed%3D2560---PLANB_NET---Join---PLANB_NET---Join---PLANB_NET---Join---PLANB_NET#%2540IRAN_V2RAY1'
      }
    ];

    AdvancedLogger.info("🚀 Starting Automated Diagnostic Suite...");

    for (var item in configs) {
      final type = item['type']!;
      final uri = item['uri']!;
      
      AdvancedLogger.info("---------------------------------------------------");
      AdvancedLogger.info("🧪 Testing $type...");
      
      // Use the service directly
      final start = DateTime.now();
      try {
        final ping = await service.getLatency(uri);
        final duration = DateTime.now().difference(start).inMilliseconds;

        AdvancedLogger.info("📊 Result for $type: $ping ms (Took ${duration}ms)");

        if (ping != -1) {
          AdvancedLogger.info("✅ $type: PASS");
          expect(ping, isNot(-1), reason: "Connection failed for $type");
        } else {
          AdvancedLogger.error("❌ $type: FAIL (Timeout or Error)");
          fail("Connection failed for $type");
        }
      } catch (e) {
        AdvancedLogger.error("💥 $type: EXCEPTION: $e");
        fail("Exception during $type test: $e");
      }
      
      // Wait a bit between tests to clear ports
      await Future.delayed(const Duration(seconds: 2));
    }
    
    AdvancedLogger.info("---------------------------------------------------");
    AdvancedLogger.info("🏁 Diagnostic Suite Completed.");
  });
}
