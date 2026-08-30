import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/binary_manager.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BinaryManager Tests', () {
    setUp(() {
      BinaryManager.debugIsWindows = null;
      BinaryManager.debugIsAndroid = null;
    });

    tearDown(() {
      BinaryManager.debugIsWindows = null;
      BinaryManager.debugIsAndroid = null;
    });

    test('ensureBinary handles Android correctly', () async {
      BinaryManager.debugIsWindows = false;
      BinaryManager.debugIsAndroid = true;

      expect(
        () => BinaryManager.ensureBinary(),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains("BinaryManager.ensureBinary() is not supported on Android."),
          ),
        ),
      );
    });

    test('ensureBinary handles Windows correctly', () async {
      BinaryManager.debugIsWindows = true;
      BinaryManager.debugIsAndroid = false;

      final result = await BinaryManager.ensureBinary();
      expect(result, isNotEmpty);
    });

    test('ensureBinary handles fallback platforms (Linux/MacOS) correctly', () async {
      BinaryManager.debugIsWindows = false;
      BinaryManager.debugIsAndroid = false;

      final result = await BinaryManager.ensureBinary();
      expect(result, equals('sing-box'));
    });
  });
}
