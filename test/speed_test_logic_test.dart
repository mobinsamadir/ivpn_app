import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';
import 'package:ivpn_new/services/test_queue.dart';
import 'dart:async';

void main() {
  group('CancellableOperation Tests', () {
    test('CancelToken triggers cancellation', () async {
      final token = CancelToken();
      bool cancelled = false;
      
      token.addOnCancel(() {
        cancelled = true;
      });
      
      token.cancel();
      expect(cancelled, isTrue);
      expect(token.isCancelled, isTrue);
    });
  });

  group('TestQueue Tests', () {
    late TestQueue queue;

    setUp(() {
      queue = TestQueue();
      queue.cancelAll(); 
    });

    test('Sequential job execution', () {
      final job1 = TestJob(index: 101, type: TestType.speed, cancelToken: CancelToken());
      final job2 = TestJob(index: 102, type: TestType.speed, cancelToken: CancelToken());
      
      print('--- Enqueueing Job 1');
      queue.enqueue(job1);
      print('Active: ${queue.activeJobIndex}, Queue Length: ${queue.queueLength}');
      
      expect(queue.activeJobIndex, 101, reason: 'Job 1 should be active immediately');
      expect(queue.queueLength, 0, reason: 'Queue should be empty as Job 1 is active');

      print('--- Enqueueing Job 2');
      queue.enqueue(job2);
      print('Active: ${queue.activeJobIndex}, Queue Length: ${queue.queueLength}');
      
      expect(queue.activeJobIndex, 101, reason: 'Job 1 should still be active');
      expect(queue.queueLength, 1, reason: 'Job 2 should be in queue');

      print('--- Finishing Job 1');
      queue.finishJob(101);
      print('Active: ${queue.activeJobIndex}, Queue Length: ${queue.queueLength}');
      
      expect(queue.activeJobIndex, 102, reason: 'Job 2 should become active');
      expect(queue.queueLength, 0, reason: 'Queue should be empty after Job 2 moves to active');

      queue.finishJob(102);
      expect(queue.isBusyAny, isFalse);
    });

    test('Cancellation of queued job', () {
      final job1 = TestJob(index: 201, type: TestType.speed, cancelToken: CancelToken());
      final job2 = TestJob(index: 202, type: TestType.speed, cancelToken: CancelToken());
      
      queue.enqueue(job1);
      queue.enqueue(job2);
      
      expect(queue.queueLength, 1);
      
      print('--- Cancelling Job 2 while it is in queue');
      job2.cancelToken.cancel();
      
      print('--- Finishing Job 1');
      queue.finishJob(201);
      print('Active: ${queue.activeJobIndex}, Queue Length: ${queue.queueLength}');
      
      expect(queue.activeJobIndex, isNull, reason: 'Job 2 should have been skipped');
      expect(queue.isBusyAny, isFalse);
    });
  });
}
