// test/vpn_core_check.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('VPN Core Diagnostics', () {
    // نام فایل اجرایی هسته وی‌پی‌ان خود را اینجا تنظیم کنید (مثلاً xray.exe یا sing-box.exe)
    // اگر نام دقیق را نمی‌دانید، ایجنت باید بر اساس گام ۱ آن را جایگذاری کند.
    const String coreBinaryName = 'xray.exe'; // یا هر اسم دیگری که پیدا شد

    test('1. Check if Core Binary exists in Build Assets', () {
      // مسیر بیلد ویندوز (جایی که برنامه اجرا می‌شود)
      final buildDir = Directory(r'build\windows\x64\runner\Debug');
      final assetsDir = Directory(p.join(buildDir.path, 'data')); // معمولاً در پوشه data است
      
      // جستجو در پوشه بیلد
      final files = buildDir.listSync(recursive: true);
      bool found = false;
      String foundPath = '';

      print('--- Scanning Build Directory for $coreBinaryName ---');
      for (var entity in files) {
        if (entity is File && entity.path.contains(coreBinaryName)) {
          found = true;
          foundPath = entity.path;
          print('✅ FOUND at: $foundPath');
        }
      }

      if (!found) {
        print('❌ ERROR: Core binary NOT found in build directory.');
        print('Files present in Debug folder:');
        buildDir.listSync().forEach((e) => print(' - ${p.basename(e.path)}'));
      }
      
      expect(found, isTrue, reason: "The VPN core binary is missing from the build folder.");
    });

    test('2. Try to Execute Core Binary (Version Check)', () async {
      // اگر فایل پیدا شد، سعی کن آن را اجرا کنی
      // این تست نشان می‌دهد آیا مشکل وابستگی (Dependency) یا پرمیشن داریم یا خیر
      
      // نکته: مسیر را دستی ست می‌کنیم چون تست محیط ایزوله دارد
      // ایجنت: لطفا اگر فایل در جای دیگری است مسیر را اصلاح کن
      const corePath = r'build\windows\x64\runner\Debug\xray.exe'; 
      
      if (File(corePath).existsSync()) {
        print('🚀 Attempting to run: $corePath -version');
        try {
          final result = await Process.run(corePath, ['-version']);
          print('STDOUT: ${result.stdout}');
          print('STDERR: ${result.stderr}');
          expect(result.exitCode, 0, reason: "Core executed but returned error code.");
        } catch (e) {
          print('❌ EXCEPTION: Could not run process. $e');
          fail("Process failed to start.");
        }
      } else {
        print('⚠️ Skipping execution test because binary is missing.');
      }
    });
  });
}