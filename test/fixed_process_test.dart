import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Fixed: Can Flutter spawn sing-box on Windows', () async {
    print('\n🔧 Fixed Windows Process Test');
    
    // 1. Absolute path
    const relativePath = 'assets/executables/windows/sing-box.exe';
    final absolutePath = p.join(Directory.current.path, relativePath);
    final exeFile = File(absolutePath);
    
    print('📂 Current directory: ${Directory.current.path}');
    print('📂 Absolute path: $absolutePath');
    print('✅ File exists: ${exeFile.existsSync()}');
    
    if (!exeFile.existsSync()) {
      throw Exception('❌ sing-box.exe not found at: $absolutePath');
    }
    
    // 2. Minimal config
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
    
    final configFile = File('${Directory.systemTemp.path}/singbox_test.json');
    await configFile.writeAsString(config, encoding: utf8);
    print('📄 Config file: ${configFile.path}');
    
    // 3. Windows-specific process spawning
    Process process;
    if (Platform.isWindows) {
      // 🚨 CRITICAL FIX: Use cmd with quoted paths
      final quotedExePath = '"$absolutePath"';
      final quotedConfigPath = '"${configFile.path}"';
      final command = '$quotedExePath run -c $quotedConfigPath';
      
      print('🚀 Starting via cmd: $command');
      
      process = await Process.start(
        'cmd',
        ['/c', command],
        runInShell: false,
        workingDirectory: Directory.current.path,
      );
    } else {
      process = await Process.start(
        absolutePath,
        ['run', '-c', configFile.path],
        runInShell: false,
      );
    }
    
    print('✅ Process started with PID: ${process.pid}');
    
    // 4. Capture outputs
    final outputCompleter = Completer<void>();
    final errorBuffer = StringBuffer();
    final outputBuffer = StringBuffer();
    bool hasStarted = false;
    
    process.stdout.transform(utf8.decoder).listen((data) {
      outputBuffer.write(data);
      print('[STDOUT] $data');
      if ((data.contains('started') || data.contains('listening')) && !hasStarted) {
        hasStarted = true;
        if (!outputCompleter.isCompleted) outputCompleter.complete();
      }
    });
    
    process.stderr.transform(utf8.decoder).listen((data) {
      errorBuffer.write(data);
      print('[STDERR] $data');
      if (data.contains('FATAL') || data.contains('not recognized')) {
        if (!outputCompleter.isCompleted) {
          outputCompleter.completeError('Fatal error: $data');
        }
      }
    });
    
    // 5. Wait with timeout
    try {
      await outputCompleter.future.timeout(const Duration(seconds: 5));
      print('✅ Sing-box started successfully!');
      
      // Wait a bit then kill
      await Future.delayed(const Duration(seconds: 1));
      process.kill();
      
      print('\n📊 Test Summary:');
      print('  - Process spawned: ✅');
      print('  - Started successfully: ✅');
      print('  - No fatal errors: ✅');
      
      expect(hasStarted, isTrue, reason: 'Sing-box should have started');
    } catch (e) {
      print('❌ Failed to start: $e');
      print('📝 Output buffer: ${outputBuffer.toString()}');
      print('🚨 Error buffer: ${errorBuffer.toString()}');
      process.kill();
      rethrow;
    } finally {
      await configFile.delete();
    }
  }, timeout: const Timeout(Duration(seconds: 10)));
}
