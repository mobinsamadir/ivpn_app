import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/binary_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BinaryManager Tests', () {
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
  });
}
