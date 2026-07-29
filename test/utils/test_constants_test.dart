import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/test_constants.dart';

void main() {
  group('TestTimeouts', () {
    test('constants return valid duration', () {
      expect(TestTimeouts.quickHealthCheck.inSeconds, 8);
      expect(TestTimeouts.fullHealthCheck.inSeconds, 15);
      expect(TestTimeouts.pingCheck.inSeconds, 5);
      expect(TestTimeouts.stabilityTest.inSeconds, 30);
      expect(TestTimeouts.speedTestSingle.inSeconds, 25);
      expect(TestTimeouts.adaptiveSpeedTest.inSeconds, 45);
      expect(TestTimeouts.configLoad.inSeconds, 35);

      expect(TestTimeouts.httpRequest.inSeconds, 8);
      expect(TestTimeouts.dnsResolution.inSeconds, 3);
      expect(TestTimeouts.tcpHandshake.inSeconds, 6);
      expect(TestTimeouts.sslHandshake.inSeconds, 5);
    });

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
