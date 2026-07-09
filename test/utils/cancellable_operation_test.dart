import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';

void main() {
  group('CancellableOperation', () {
    test('completes successfully if not cancelled', () async {
      final future = Future.value(42);
      final operation = CancellableOperation<int>(future);

      expect(operation.isCancelled, isFalse);
      expect(await operation.value, equals(42));
    });

    test('throws error if underlying future throws', () async {
      final exception = Exception('Something went wrong');
      final future = Future<int>.error(exception);
      final operation = CancellableOperation<int>(future);

      expect(operation.value, throwsA(equals(exception)));
    });

    test('throws OperationCancelledException when cancelled before completion', () async {
      final completer = Completer<int>();
      final operation = CancellableOperation<int>(completer.future);

      operation.cancel();

      expect(operation.isCancelled, isTrue);
      expect(operation.value, throwsA(isA<OperationCancelledException>()));

      // Complete the underlying future later to ensure it doesn't cause uncaught errors
      completer.complete(42);
    });

    test('throws OperationCancelledException when cancelled before error', () async {
      final completer = Completer<int>();
      final operation = CancellableOperation<int>(completer.future);

      operation.cancel();

      expect(operation.isCancelled, isTrue);
      expect(operation.value, throwsA(isA<OperationCancelledException>()));

      // Complete the underlying future with error later to ensure it doesn't cause uncaught errors
      completer.completeError(Exception('Late error'));
    });

    test('does nothing when cancelled after completion', () async {
      final completer = Completer<int>();
      final operation = CancellableOperation<int>(completer.future);

      completer.complete(42);
      final value = await operation.value;

      expect(value, equals(42));

      operation.cancel();

      // isCancelled should still be false because it was already completed
      expect(operation.isCancelled, isFalse);
    });
  });

  group('CancelToken', () {
    test('initial state is not cancelled', () {
      final token = CancelToken();
      expect(token.isCancelled, isFalse);
      expect(token.reason, isNull);
      expect(token.wasTimeout, isFalse);
    });

    test('triggers callback when cancelled', () {
      final token = CancelToken();
      bool wasCalled = false;

      token.addOnCancel(() {
        wasCalled = true;
      });

      token.cancel();

      expect(token.isCancelled, isTrue);
      expect(token.reason, equals(CancelReason.user));
      expect(wasCalled, isTrue);
    });

    test('triggers multiple callbacks when cancelled', () {
      final token = CancelToken();
      int callCount = 0;

      token.addOnCancel(() => callCount++);
      token.addOnCancel(() => callCount++);

      token.cancel();

      expect(callCount, equals(2));
    });

    test('triggers callback immediately if already cancelled', () {
      final token = CancelToken();
      token.cancel();

      bool wasCalled = false;
      token.addOnCancel(() {
        wasCalled = true;
      });

      expect(wasCalled, isTrue);
    });

    test('markAsTimeout sets correct reason', () {
      final token = CancelToken();
      token.markAsTimeout();

      expect(token.isCancelled, isTrue);
      expect(token.reason, equals(CancelReason.timeout));
      expect(token.wasTimeout, isTrue);
    });

    test('throwIfCancelled throws when cancelled', () {
      final token = CancelToken();
      token.cancel();

      expect(() => token.throwIfCancelled(), throwsA(isA<OperationCancelledException>()));
    });

    test('throwIfCancelled does nothing when not cancelled', () {
      final token = CancelToken();

      // Should not throw
      expect(() => token.throwIfCancelled(), returnsNormally);
    });

    test('OperationCancelledException toString contains message', () {
      final exception = OperationCancelledException('Test message');
      expect(exception.toString(), equals('OperationCancelledException: Test message'));
    });
  });
}
