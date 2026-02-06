import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/singbox_config_generator.dart';
import 'package:ivpn_new/utils/file_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock Method Channel for path_provider
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (message) async {
         return Directory.systemTemp.path;
      });
  
  // Mock Logger to avoid file writes if possible, or let it write to temp
  // FileLogger.init() will use the mocked path_provider
  
  test('Generate VMess Config', () async {
      const vmessLink = "vmess://eyJhZGQiOiI4NS4xOTUuMTAxLjEyMiIsImFpZCI6IjAiLCJhbHBuIjoiIiwiZnAiOiIiLCJob3N0IjoiIiwiaWQiOiJmM2Q0MTY3ZS1iMTVlLTRlNDYtODJlOS05Mjg2ZWY5M2ZkYTciLCJuZXQiOiJ0Y3AiLCJwYXRoIjoiIiwicG9ydCI6IjQwODc4IiwicHMiOiJJUi1ASVJBTl9WMlJBWTEiLCJzY3kiOiJhdXRvIiwic25pIjoiIiwidGxzIjoiIiwidHlwZSI6Im5vbmUiLCJ2IjoiMiJ9";
      
      print("Genering VMess Config...");
      
      final configBlock = SingboxConfigGenerator.generatePingConfig(
        rawLink: vmessLink, 
        socksPort: 20808, 
        httpPort: 20809
      );
      
      final file = File('vmess_debug.json');
      await file.writeAsString(configBlock);
      print("✅ Config written to vmess_debug.json");
      print(configBlock);
  });
}
