import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Test different Windows spawn methods', () async {
    print('\n🔍 Testing Windows Process Spawning Methods\n');
    
    // Normalize path for Windows
    const relativePath = 'assets/executables/windows/sing-box.exe';
    final absolutePath = p.join(Directory.current.path, relativePath);
    final windowsPath = absolutePath.replaceAll('/', '\\');
    
    print('📂 Relative: $relativePath');
    print('📂 Absolute: $absolutePath');
    print('📂 Windows: $windowsPath');
    print('📂 Exists: ${File(absolutePath).existsSync()}\n');
    
    // Method 1: Process.run without shell
    print('🧪 Method 1: Process.run (no shell)');
    try {
      final r1 = await Process.run(
        absolutePath,
        ['version'],
        runInShell: false,
      );
      print('✅ Exit code: ${r1.exitCode}');
      print('📝 Output: ${r1.stdout.toString().trim()}');
      if (r1.stderr.toString().isNotEmpty) {
        print('⚠️ Stderr: ${r1.stderr}');
      }
    } catch (e) {
      print('❌ Failed: $e');
    }
    
    print('\n🧪 Method 2: Process.run (with shell)');
    try {
      final r2 = await Process.run(
        absolutePath,
        ['version'],
        runInShell: true,
      );
      print('✅ Exit code: ${r2.exitCode}');
      print('📝 Output: ${r2.stdout.toString().trim()}');
      if (r2.stderr.toString().isNotEmpty) {
        print('⚠️ Stderr: ${r2.stderr}');
      }
    } catch (e) {
      print('❌ Failed: $e');
    }
    
    print('\n🧪 Method 3: Process.run (Windows path, no shell)');
    try {
      final r3 = await Process.run(
        windowsPath,
        ['version'],
        runInShell: false,
      );
      print('✅ Exit code: ${r3.exitCode}');
      print('📝 Output: ${r3.stdout.toString().trim()}');
      if (r3.stderr.toString().isNotEmpty) {
        print('⚠️ Stderr: ${r3.stderr}');
      }
    } catch (e) {
      print('❌ Failed: $e');
    }
    
    print('\n🧪 Method 4: Process.start (no shell)');
    try {
      final p4 = await Process.start(
        absolutePath,
        ['version'],
        runInShell: false,
      );
      final stdout = await p4.stdout.transform(utf8.decoder).join();
      final stderr = await p4.stderr.transform(utf8.decoder).join();
      final exitCode = await p4.exitCode;
      print('✅ Exit code: $exitCode');
      print('📝 Output: ${stdout.trim()}');
      if (stderr.isNotEmpty) {
        print('⚠️ Stderr: $stderr');
      }
    } catch (e) {
      print('❌ Failed: $e');
    }
    
    print('\n🧪 Method 5: Process.start (with shell)');
    try {
      final p5 = await Process.start(
        absolutePath,
        ['version'],
        runInShell: true,
      );
      final stdout = await p5.stdout.transform(utf8.decoder).join();
      final stderr = await p5.stderr.transform(utf8.decoder).join();
      final exitCode = await p5.exitCode;
      print('✅ Exit code: $exitCode');
      print('📝 Output: ${stdout.trim()}');
      if (stderr.isNotEmpty) {
        print('⚠️ Stderr: $stderr');
      }
    } catch (e) {
      print('❌ Failed: $e');
    }
    
    print('\n✅ Test complete - check which method worked above');
  });
}
