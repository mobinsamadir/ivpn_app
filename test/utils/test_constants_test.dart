import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/test_constants.dart';

void main() {
  group('TestTimeouts', () {
    test('withTimeout returns future value if completes before timeout',
        () async {
      final future =
          Future.delayed(const Duration(milliseconds: 10), () => 'success');

      final result = await TestTimeouts.withTimeout(
        future,
        timeout: const Duration(milliseconds: 50),
      );

      expect(result, 'success');
    });

    test(
        'withTimeout throws TimeoutException if timeout occurs without onTimeout',
        () async {
      final future =
          Future.delayed(const Duration(milliseconds: 50), () => 'success');

      expect(
        () => TestTimeouts.withTimeout(
          future,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('withTimeout returns onTimeout result if timeout occurs', () async {
      final future =
          Future.delayed(const Duration(milliseconds: 50), () => 'success');

      final result = await TestTimeouts.withTimeout(
        future,
        timeout: const Duration(milliseconds: 10),
        onTimeout: () => 'fallback',
      );

      expect(result, 'fallback');
    });
  });
}
