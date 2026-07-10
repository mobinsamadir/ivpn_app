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
      final result = await SmartPinger.pingWithRetry(
        'https://google.com',
        null,
        maxRetries: 3,
        timeout: const Duration(milliseconds: 100),
        pingSingleInjector: (endpoint, token, {required timeout}) async {
          attempts++;
          return PingResult(
            endpoint: endpoint,
            latency: -1,
            isSuccess: false,
            error: 'Mocked connection refused',
          );
        },
      );
      expect(result.isSuccess, isFalse);
      expect(result.latency, -1);
      expect(attempts, 3);
    });

    test('Transient failure recovers on the second attempt', () async {
      int attempts = 0;
      final result = await SmartPinger.pingWithRetry(
        'https://google.com',
        null,
        maxRetries: 3,
        timeout: const Duration(milliseconds: 100),
        pingSingleInjector: (endpoint, token, {required timeout}) async {
          attempts++;
          if (attempts == 1) {
            return PingResult(
              endpoint: endpoint,
              latency: -1,
              isSuccess: false,
              error: 'Mocked connection refused',
            );
          }
          return PingResult(
            endpoint: endpoint,
            latency: 10,
            isSuccess: true,
          );
        },
      );
      expect(result.isSuccess, isTrue);
      expect(result.latency, greaterThanOrEqualTo(0));
      expect(attempts, 2);
    });

    test('Timeout scenario retries correctly', () async {
      int attempts = 0;
      final result = await SmartPinger.pingWithRetry(
        'https://google.com',
        null,
        maxRetries: 2,
        timeout: const Duration(milliseconds: 100),
        pingSingleInjector: (endpoint, token, {required timeout}) async {
          attempts++;
          return PingResult(
            endpoint: endpoint,
            latency: -1,
            isSuccess: false,
            error: 'Mocked timeout',
          );
        },
      );
      expect(result.isSuccess, isFalse);
      expect(result.latency, -1);
      expect(attempts, 2);
    });

    test('Immediate abort on Cancellation skips retries', () async {
      int attempts = 0;
      final token = CancelToken();

      final future = SmartPinger.pingWithRetry(
        'https://google.com',
        token,
        maxRetries: 3,
        timeout: const Duration(milliseconds: 100),
        pingSingleInjector: (endpoint, tokenInner, {required timeout}) async {
          attempts++;
          // Cancel during the first attempt
          token.cancel();
          // Simulating an exception that would normally trigger a retry if not cancelled
          throw Exception('Mocked failure');
        },
      );

      await expectLater(future, throwsA(isA<OperationCancelledException>()));
      // Ensure only 1 attempt was made despite maxRetries = 3
      expect(attempts, 1);
    });
  });

  group('SmartPinger Staggered Concurrency', () {
    test('Returns fastest result without waiting for first timeout', () async {
      int attempts = 0;
      final stopwatch = Stopwatch()..start();

      final result = await SmartPinger.pingWithRetry(
        'https://staggered.com',
        null,
        maxRetries: 2,
        timeout: const Duration(seconds: 2), // High timeout
        pingSingleInjector: (endpoint, token, {required timeout}) async {
          attempts++;
          if (attempts == 1) {
            // First attempt hangs for 2 seconds (exceeding the stagger delay of 500ms)
            await Future.delayed(const Duration(seconds: 2));
            return PingResult(
              endpoint: endpoint,
              latency: -1,
              isSuccess: false,
              error: 'timeout',
            );
          } else {
            // Second attempt (fired after 500ms stagger) returns quickly
            await Future.delayed(const Duration(milliseconds: 50));
            return PingResult(
              endpoint: endpoint,
              latency: 10,
              isSuccess: true,
            );
          }
        },
      );

      stopwatch.stop();

      expect(result.isSuccess, isTrue);
      expect(result.latency, 10);

      // The total time should be roughly staggered delay (500ms) + second attempt duration (50ms)
      // We check that it didn't wait the full 2 seconds for the first attempt to finish
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));
      expect(attempts, 2);
    });

    test('CancelToken properly aborts all in-flight pings in staggered mode', () async {
      int attemptsLaunched = 0;
      final token = CancelToken();

      final future = SmartPinger.pingWithRetry(
        'https://cancel.com',
        token,
        maxRetries: 3,
        timeout: const Duration(seconds: 2),
        pingSingleInjector: (endpoint, innerToken, {required timeout}) async {
          attemptsLaunched++;
          if (attemptsLaunched == 2) {
            // Cancel when the second attempt is launched
            token.cancel();
            // Since our mock isn't actually bound to the cancel token (unlike real Socket.connect),
            // we simulate what _pingSingle would do when token is cancelled mid-flight
            throw OperationCancelledException();
          }
          await Future.delayed(const Duration(seconds: 1));
          // If it was already cancelled, real _pingSingle throws. So we throw if token is cancelled.
          if (token.isCancelled) throw OperationCancelledException();
          return PingResult(endpoint: endpoint, latency: 10, isSuccess: true);
        },
      );

      await expectLater(future, throwsA(isA<OperationCancelledException>()));
      // It should launch the 1st attempt, wait 500ms, launch the 2nd attempt, and then cancel.
      // So max attempts launched should be 2, not 3.
      expect(attemptsLaunched, 2);
    });
  });
}
