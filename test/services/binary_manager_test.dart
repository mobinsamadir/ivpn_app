import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/binary_manager.dart';

void main() {
  group('BinaryManager Tests', () {
    tearDown(() {
      BinaryManager.debugIsWindows = null;
      BinaryManager.debugIsAndroid = null;
    });

    test('ensureBinary returns executable path on Windows', () async {
      BinaryManager.debugIsWindows = true;
      BinaryManager.debugIsAndroid = false;

      final result = await BinaryManager.ensureBinary();
      expect(result, isA<String>());
    });

    test('ensureBinary throws UnsupportedError on Android', () async {
      BinaryManager.debugIsWindows = false;
      BinaryManager.debugIsAndroid = true;

      expect(
        () async => await BinaryManager.ensureBinary(),
        throwsA(isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('not supported on Android'),
        )),
      );
    });

    test('ensureBinary returns "sing-box" on other platforms', () async {
      BinaryManager.debugIsWindows = false;
      BinaryManager.debugIsAndroid = false;

      final result = await BinaryManager.ensureBinary();
      expect(result, equals('sing-box'));
    });
  });
}
