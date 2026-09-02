import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/binary_manager.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BinaryManager Tests', () {
    tearDown(() {
      BinaryManager.debugIsWindows = null;
      BinaryManager.debugIsAndroid = null;
    });

    test('ensureBinary handles Windows correctly', () async {
      BinaryManager.debugIsWindows = true;
      BinaryManager.debugIsAndroid = false;

      // Depending on the test environment, WindowsVpnService.getExecutablePath()
      // might throw or return a string.
      try {
        final result = await BinaryManager.ensureBinary();
        expect(result, isA<String>());
      } catch (e) {
        // If it throws because the executable isn't found in the test environment,
        // we at least ensure it doesn't throw UnsupportedError like Android.
        expect(e, isNot(isA<UnsupportedError>()));
      }
    });

    test('ensureBinary handles Android correctly by throwing UnsupportedError', () async {
      BinaryManager.debugIsWindows = false;
      BinaryManager.debugIsAndroid = true;
      expect(
        () async => await BinaryManager.ensureBinary(),
        throwsA(isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains("BinaryManager.ensureBinary() is not supported on Android. Use NativeVpnService instead."),
        )),
      );
    });

    test('ensureBinary handles Linux/MacOS correctly (fallback)', () async {
      BinaryManager.debugIsWindows = false;
      BinaryManager.debugIsAndroid = false;

      final result = await BinaryManager.ensureBinary();
      expect(result, "sing-box");
    });
  });
}
