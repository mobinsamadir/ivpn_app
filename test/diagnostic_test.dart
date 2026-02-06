import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';

void main() {
  test('Diagnostic: Check sing-box executable path', () async {
    print('\n🔍 Diagnostic Test Starting...');
    
    final vpnService = WindowsVpnService();
    final exePath = await vpnService.getExecutablePath();
    
    print('📂 Executable path: $exePath');
    
    final file = File(exePath);
    final exists = file.existsSync();
    
    print('✅ File exists: $exists');
    
    if (exists) {
      final stat = file.statSync();
      print('📊 File size: ${stat.size} bytes');
      print('📅 Modified: ${stat.modified}');
    }
    
    expect(exists, isTrue, reason: 'sing-box.exe must exist at $exePath');
    
    // Try to run version command
    print('\n🚀 Testing version command...');
    try {
      final result = await Process.run(exePath, ['version']);
      print('✅ Exit code: ${result.exitCode}');
      print('📝 Output: ${result.stdout}');
      if (result.stderr.toString().isNotEmpty) {
        print('⚠️ Stderr: ${result.stderr}');
      }
      
      expect(result.exitCode, 0, reason: 'Version command should succeed');
    } catch (e) {
      print('❌ Error running version: $e');
      rethrow;
    }
  });
}
