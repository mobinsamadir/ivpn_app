import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/test_queue.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';
import 'package:ivpn_new/services/test_job.dart';
import 'dart:async';

void main() {
  group('TestQueue Tests', () {
    late TestQueue queue;

    setUp(() {
      queue = TestQueue(category: 'test');
    });

    test('enqueue adds job to queue and processes it', () async {
      bool taskRun = false;

      final future = queue.enqueue((token, jobId) async {
        taskRun = true;
      }, name: 'TestJob');

      expect(queue.isBusy, true);

      await future;

      expect(taskRun, true);
      expect(queue.isBusy, false);
      expect(queue.queueLength, 0);
    });

    test('cancelAll cancels running and pending jobs', () async {
      // Enqueue a job that takes some time
      queue.enqueue((token, jobId) async {
        await Future.delayed(const Duration(milliseconds: 100));
      }, name: 'Task1');

      // Enqueue a second job
      final future2 = queue.enqueue((token, jobId) async {}, name: 'Task2');

      expect(queue.isBusy, true);
      expect(queue.queueLength, 1); // 1 active, 1 in queue

      // Cancel all
      queue.cancelAll();

      // Task 2 should complete with error immediately
      expect(future2, throwsA(isA<OperationCancelledException>()));

      expect(queue.isBusy, false);
      expect(queue.queueLength, 0);
    });

    test('isJobBusy returns true for active and pending jobs', () async {
      queue.enqueue((token, jobId) async {
        await Future.delayed(const Duration(milliseconds: 100));
      }, name: 'Job #1');

      queue.enqueue((token, jobId) async {
        await Future.delayed(const Duration(milliseconds: 100));
      }, name: 'Job #2');

      expect(queue.isJobBusy(1), true);
      expect(queue.isJobBusy(2), true);
      expect(queue.isJobBusy(3), false);
    });

    test('Job timeout works', () async {
      final future = queue.enqueue((token, jobId) async {
        await Future.delayed(const Duration(milliseconds: 200));
      }, name: 'TimeoutJob', timeout: const Duration(milliseconds: 50));

      await expectLater(future, throwsA(isA<TimeoutException>()));
    });

    test('Job throws custom exception', () async {
      final future = queue.enqueue((token, jobId) async {
        throw Exception("Custom error");
      }, name: 'ErrorJob');

      await expectLater(future, throwsException);
    });

    test('Job timeout triggers fallback if type is provided', () async {
      final future = queue.enqueue((token, jobId) async {
        await Future.delayed(const Duration(milliseconds: 200));
      },
          name: 'TimeoutJobWithType',
          timeout: const Duration(milliseconds: 50),
          type: TestType.ping);

      await expectLater(future, throwsA(isA<TimeoutException>()));
    });
  });
}
