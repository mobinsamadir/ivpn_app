import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/binary_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BinaryManager Tests', () {
    tearDown(() {
      BinaryManager.debugIsWindows = null;
      BinaryManager.debugIsAndroid = null;
    });

    test('ensureBinary handles different platforms correctly', () async {
      try {
        final result = await BinaryManager.ensureBinary();
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          expect(result, isNotEmpty);
        }
      } catch (e) {
        if (Platform.isAndroid) {
          expect(e, isA<UnsupportedError>());
          expect(
              (e as UnsupportedError).message,
              contains(
                  "BinaryManager.ensureBinary() is not supported on Android."));
        } else {
          rethrow;
        }
      }
    });

    test('ensureBinary handles Android properly using mocks', () async {
      BinaryManager.debugIsAndroid = true;
      BinaryManager.debugIsWindows = false;

      try {
        await BinaryManager.ensureBinary();
        fail('Should have thrown UnsupportedError');
      } catch (e) {
        expect(e, isA<UnsupportedError>());
        expect(
            (e as UnsupportedError).message,
            contains(
                "BinaryManager.ensureBinary() is not supported on Android."));
      }
    });

    test('ensureBinary handles fallback properly using mocks', () async {
      BinaryManager.debugIsAndroid = false;
      BinaryManager.debugIsWindows = false;

      final result = await BinaryManager.ensureBinary();
      expect(result, 'sing-box');
    });
  });
}
