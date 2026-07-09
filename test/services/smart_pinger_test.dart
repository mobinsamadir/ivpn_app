import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/smart_pinger.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';

void main() {
  group('SmartPinger Cancellation', () {
    test('Pre-emptive cancellation prevents network calls and throws',
        () async {
      final token = CancelToken()..cancel();

      // We expect the Future to throw OperationCancelledException immediately
      expect(
        () => SmartPinger.pingMultiple(
          endpoints: ['https://google.com'],
          cancelToken: token,
        ),
        throwsA(isA<OperationCancelledException>()),
      );
    });

    test('Mid-flight cancellation aborts the operation and throws', () async {
      final token = CancelToken();

      // Trigger cancel shortly after the ping starts
      Future.delayed(const Duration(milliseconds: 10), () {
        token.cancel();
      });

      // We use a non-existent or slow endpoint to ensure we can cancel it mid-flight
      // Alternatively, relying on network delay might be enough, but using a guaranteed
      // delay approach via endpoint might be better. We use an IP that drops packets
      // or just expect the cancellation to hit while the socket is trying to connect.
      expect(
        () => SmartPinger.pingMultiple(
          // Example IP that is unroutable/drops packets (TEST-NET-1) to simulate hanging
          endpoints: ['https://192.0.2.1'],
          cancelToken: token,
          timeoutPerPing: const Duration(seconds: 2),
        ),
        throwsA(isA<OperationCancelledException>()),
      );
    });
  });
}
