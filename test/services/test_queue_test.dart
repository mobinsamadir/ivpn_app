import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/test_queue.dart';
import 'package:ivpn_new/services/test_job.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';

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
      bool task1Finished = false;
      bool task2Finished = false;

      // Enqueue a job that takes some time
      final future1 = queue.enqueue((token, jobId) async {
        await Future.delayed(const Duration(milliseconds: 100));
        task1Finished = true;
      }, name: 'Task1');

      // Enqueue a second job
      final future2 = queue.enqueue((token, jobId) async {
        task2Finished = true;
      }, name: 'Task2');

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

      // Do not call cancelAll because it fails pending jobs
      // causing the test itself to fail due to unhandled async error.
    });
  });
}
