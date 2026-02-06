import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:ivpn_new/services/latency_service.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (message) async {
        return null;
      });
  
  // Mock path_provider
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (message) async {
         return Directory.systemTemp.path;
      });

  test('Smoke Test: Can LatencyService start sing-box?', () async {
    print('\n🚀 Starting Smoke Test...');
    
    final vpnService = WindowsVpnService();
    final latencyService = LatencyService(vpnService);
    
    // Use the EXACT config that works standalone
    const vmessUri = "vmess://eyJhZGQiOiI4NS4xOTUuMTAxLjEyMiIsImFpZCI6IjAiLCJhbHBuIjoiIiwiZnAiOiIiLCJob3N0IjoiIiwiaWQiOiJmM2Q0MTY3ZS1iMTVlLTRlNDYtODJlOS05Mjg2ZWY5M2ZkYTciLCJuZXQiOiJ0Y3AiLCJwYXRoIjoiIiwicG9ydCI6IjQwODc4IiwicHMiOiJJUi1ASVJBTl9WMlJBWTEiLCJzY3kiOiJhdXRvIiwic25pIjoiIiwidGxzIjoiIiwidHlwZSI6Im5vbmUiLCJ2IjoiMiJ9";
    
    print('📦 Testing VMess config...');
    
    final result = await latencyService.getLatency(
      vmessUri,
      onLog: (msg) => print('  [LOG] $msg'),
    ).timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        print('⏰ TIMEOUT after 20 seconds');
        return -1;
      },
    );
    
    print('✅ Result: $result ms');
    
    if (result == -1) {
      print('❌ Test FAILED: Latency returned -1');
    } else {
      print('✅ Test PASSED: Got latency $result ms');
    }
    
    expect(result, isNot(-1), reason: 'Latency should not be -1 (timeout/error)');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
