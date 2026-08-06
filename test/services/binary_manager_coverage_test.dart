import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/binary_manager.dart';

void main() {
  group('BinaryManager Tests coverage', () {
    test('ensureBinary fallback string', () async {
      try {
        final result = await BinaryManager.ensureBinary();
        expect(result, isNotNull);
      } catch (e) {
        expect(e, isA<UnsupportedError>());
      }
    });
  });
}
