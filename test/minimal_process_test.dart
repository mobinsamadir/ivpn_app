import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Minimal: Can Flutter spawn sing-box?', () async {
    print('\n🔍 Starting minimal process test...');
    
    // 1. Executable path
    const exePath = 'assets/executables/windows/sing-box.exe';
    final exeFile = File(exePath);
    
    if (!exeFile.existsSync()) {
      throw Exception('❌ sing-box.exe not found at: $exePath');
    }
    
    print('✅ Executable exists: ${exeFile.path}');
    print('📊 File size: ${exeFile.lengthSync()} bytes');
    
    // 2. Minimal config that worked in PowerShell
    const config = '''
{
  "log": {"level": "debug", "output": "stderr"},
  "inbounds": [{
    "type": "http",
    "tag": "test",
    "listen": "127.0.0.1",
    "listen_port": 59999
  }],
  "outbounds": [{
    "type": "direct",
    "tag": "direct"
  }]
}
''';
    
    // 3. Save temp config file
    final configFile = File('test_minimal_config.json');
    await configFile.writeAsString(config);
    print('📄 Config file created: ${configFile.path}');
    
    // 4. Start sing-box WITH runInShell on Windows
    print('🚀 Starting sing-box process...');
    final process = await Process.start(
      exePath,
      ['run', '-c', configFile.path],
      runInShell: Platform.isWindows, // CRITICAL for Windows
    );
    
    print('✅ Process started with PID: ${process.pid}');
    
    // 5. Capture output immediately
    bool hasOutput = false;
    bool hasError = false;
    
    process.stdout.transform(utf8.decoder).listen((data) {
      hasOutput = true;
      print('[STDOUT] $data');
    });
    
    process.stderr.transform(utf8.decoder).listen((data) {
      hasError = true;
      print('[STDERR] $data');
    });
    
    // 6. Wait 3 seconds then check
    print('⏳ Waiting 3 seconds for startup...');
    await Future.delayed(const Duration(seconds: 3));
    
    // 7. Check if process is still alive
    bool processStillRunning = true;
    try {
      final exitCode = await process.exitCode.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () {
          processStillRunning = true;
          return -999; // Sentinel value
        },
      );
      
      if (exitCode != -999) {
        processStillRunning = false;
        print('⚠️ Process exited early with code: $exitCode');
      }
    } catch (e) {
      print('❌ Error checking process: $e');
    }
    
    if (processStillRunning) {
      print('✅ Process still running after 3 seconds - SUCCESS!');
      process.kill();
      print('🧹 Process killed for cleanup');
    }
    
    // 8. Cleanup
    await configFile.delete();
    
    print('\n📊 Test Summary:');
    print('  - Process started: ✅');
    print('  - Had stdout: ${hasOutput ? "✅" : "❌"}');
    print('  - Had stderr: ${hasError ? "✅" : "❌"}');
    print('  - Still running after 3s: ${processStillRunning ? "✅" : "❌"}');
    
    // 9. Success if process started and ran for at least 3 seconds
    expect(processStillRunning, isTrue, 
      reason: 'Process should still be running after 3 seconds');
  }, timeout: const Timeout(Duration(seconds: 10)));
}
