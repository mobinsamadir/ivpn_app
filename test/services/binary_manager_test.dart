import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/binary_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BinaryManager Tests', () {
    setUp(() {
      BinaryManager.debugIsWindows = null;
      BinaryManager.debugIsAndroid = null;
    });

    test('ensureBinary handles fallback (Linux/MacOS) correctly', () async {
      BinaryManager.debugIsWindows = false;
      BinaryManager.debugIsAndroid = false;

      final result = await BinaryManager.ensureBinary();
      expect(result, 'sing-box');
    });

    test('ensureBinary throws UnsupportedError on Android', () async {
      BinaryManager.debugIsWindows = false;
      BinaryManager.debugIsAndroid = true;

      try {
        await BinaryManager.ensureBinary();
        fail('Should have thrown UnsupportedError on Android');
      } catch (e) {
        expect(e, isA<UnsupportedError>());
        expect(
            (e as UnsupportedError).message,
            contains(
                "BinaryManager.ensureBinary() is not supported on Android."));
      }
    });

    test('ensureBinary on Windows calls WindowsVpnService.getExecutablePath', () async {
      BinaryManager.debugIsWindows = true;
      BinaryManager.debugIsAndroid = false;

      final result = await BinaryManager.ensureBinary();
      // On non-Windows OS, we can't fully mock getExecutablePath since it's static and checks Directory.current
      // But it should return a String that ends with sing-box.exe based on its implementation
      expect(result, isA<String>());
      expect(result, endsWith('sing-box.exe'));
    });
  });
}
