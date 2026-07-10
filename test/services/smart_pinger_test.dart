import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/smart_pinger.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';

class MockSocket implements Socket {
  @override
  void destroy() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
      Timer(const Duration(milliseconds: 10), () {
        token.cancel();
      });

      await expectLater(
        SmartPinger.pingMultiple(
          endpoints: ['https://192.0.2.1'],
          cancelToken: token,
          timeoutPerPing: const Duration(seconds: 2),
        ),
        throwsA(isA<OperationCancelledException>()),
      );
    });
  });

  group('SmartPinger Retry Logic', () {
    test('Consistent failure exhausts maxRetries and returns failure',
        () async {
      int attempts = 0;
      await IOOverrides.runZoned(() async {
        final result = await SmartPinger.pingWithRetry(
          'https://google.com',
          null,
          maxRetries: 3,
          timeout: const Duration(milliseconds: 100),
        );
        expect(result.isSuccess, isFalse);
        expect(result.latency, -1);
        expect(attempts, 3);
      }, socketConnect: (host, port,
          {sourceAddress, int? sourcePort, timeout}) async {
        attempts++;
        throw SocketException('Mocked connection refused');
      });
    });

    test('Transient failure recovers on the second attempt', () async {
      int attempts = 0;
      await IOOverrides.runZoned(() async {
        final result = await SmartPinger.pingWithRetry(
          'https://google.com',
          null,
          maxRetries: 3,
          timeout: const Duration(milliseconds: 100),
        );
        expect(result.isSuccess, isTrue);
        expect(result.latency, greaterThanOrEqualTo(0));
        expect(attempts, 2);
      }, socketConnect: (host, port,
          {sourceAddress, int? sourcePort, timeout}) async {
        attempts++;
        if (attempts == 1) {
          throw SocketException('Mocked connection refused');
        }
        return MockSocket();
      });
    });

    test('Timeout scenario retries correctly', () async {
      int attempts = 0;
      await IOOverrides.runZoned(() async {
        final result = await SmartPinger.pingWithRetry(
          'https://google.com',
          null,
          maxRetries: 2,
          timeout: const Duration(milliseconds: 100),
        );
        expect(result.isSuccess, isFalse);
        expect(result.latency, -1);
        expect(attempts, 2);
      }, socketConnect: (host, port,
          {sourceAddress, int? sourcePort, timeout}) async {
        attempts++;
        throw TimeoutException('Mocked timeout');
      });
    });

    test('Immediate abort on Cancellation skips retries', () async {
      int attempts = 0;
      final token = CancelToken();

      await IOOverrides.runZoned(() async {
        final future = SmartPinger.pingWithRetry(
          'https://google.com',
          token,
          maxRetries: 3,
          timeout: const Duration(milliseconds: 100),
        );

        await expectLater(future, throwsA(isA<OperationCancelledException>()));
      }, socketConnect: (host, port,
          {sourceAddress, int? sourcePort, timeout}) async {
        attempts++;
        // Cancel during the first attempt
        token.cancel();
        // Simulate an exception that would normally trigger a retry if not cancelled
        throw SocketException('Mocked failure');
      });

      // Ensure only 1 attempt was made despite maxRetries = 3
      expect(attempts, 1);
    });
  });
}
