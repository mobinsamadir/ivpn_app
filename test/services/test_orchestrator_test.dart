import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/test_orchestrator.dart';
import 'package:ivpn_new/services/test_queue.dart';
import 'package:ivpn_new/utils/test_constants.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';

void main() {
  group('TestOrchestrator Coverage', () {
    setUp(() {
      TestOrchestrator.cancelAll();
    });

    test('enqueueHealthCheck configures timeouts correctly', () async {
      bool quickCalled = false;
      bool fullCalled = false;

      await TestOrchestrator.enqueueHealthCheck((token, id) async {
        quickCalled = true;
      }, quick: true);

      await TestOrchestrator.enqueueHealthCheck((token, id) async {
        fullCalled = true;
      }, quick: false);

      // wait briefly for async queue processing
      await Future.delayed(const Duration(milliseconds: 50));

      expect(quickCalled, true);
      expect(fullCalled, true);
    });

    test('enqueueStabilityTest works', () async {
      final completer = Completer<void>();
      TestOrchestrator.enqueueStabilityTest((token, id) async {
        completer.complete();
      });
      await completer.future;
      expect(TestOrchestrator.stabilityQueue.queueLength, 0);
    });

    test('enqueuePingTest works', () async {
      final completer = Completer<void>();
      TestOrchestrator.enqueuePingTest((token, id) async {
        completer.complete();
      });
      await completer.future;
      expect(TestOrchestrator.pingQueue.queueLength, 0);
    });

    test('enqueueAdaptiveTest works', () async {
      final completer = Completer<void>();
      TestOrchestrator.enqueueAdaptiveTest((token, id) async {
        completer.complete();
      });
      await completer.future;
    });

    test('Cancellation methods trigger individual queues', () {
      TestOrchestrator.enqueueSpeedTest(
          (token, id) async => await Future.delayed(Duration(seconds: 5)));
      TestOrchestrator.enqueueStabilityTest(
          (token, id) async => await Future.delayed(Duration(seconds: 5)));

      TestOrchestrator.cancelSpeedTests();
      TestOrchestrator.cancelStabilityTests();

      expect(TestOrchestrator.speedQueue.queueLength, 0);
      expect(TestOrchestrator.stabilityQueue.queueLength, 0);
    });

    test('getStatus and getStatusString return valid data', () {
      final status = TestOrchestrator.getStatus();
      expect(status.containsKey('speedQueue'), true);
      expect(status.containsKey('stabilityQueue'), true);
      expect(status.containsKey('healthQueue'), true);
      expect(status.containsKey('pingQueue'), true);
      expect(status.containsKey('isAnyBusy'), true);

      final statusString = TestOrchestrator.getStatusString();
      expect(statusString, contains('Queued: S:'));
      expect(statusString, contains('B:'));
      expect(statusString, contains('H:'));
      expect(statusString, contains('P:'));
    });
  });
}
