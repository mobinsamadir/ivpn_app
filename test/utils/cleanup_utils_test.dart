import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ivpn_new/utils/cleanup_utils.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';

class MockProcess extends Mock implements Process {}

class MockHttpClient extends Mock implements HttpClient {}

class MockStreamSubscription extends Mock implements StreamSubscription {}

class MockTimer extends Mock implements Timer {}

class FakeProcessSignal extends Fake implements ProcessSignal {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeProcessSignal());
  });

  group('CleanupUtils', () {
    setUp(() {
      // Clean up maps before each test.
      // Need to use emergencyCleanup to make sure state is clean.
      CleanupUtils.emergencyCleanup();
    });

    test('registerJob registers token and resources list', () async {
      final token = CancelToken();
      CleanupUtils.registerJob('test-job-1', token);

      final process = MockProcess();
      when(() => process.kill(any())).thenReturn(true);
      when(() => process.pid).thenReturn(100);

      CleanupUtils.registerResource('test-job-1', process);

      await CleanupUtils.cleanupJobResources('test-job-1');

      verify(() => process.kill(ProcessSignal.sigkill)).called(1);
      expect(token.isCancelled, isTrue);
    });

    test('cleanupJobResources handles multiple resource types correctly',
        () async {
      final token = CancelToken();
      CleanupUtils.registerJob('multi-resource-job', token);

      final process = MockProcess();
      when(() => process.kill(any())).thenReturn(true);
      when(() => process.pid).thenReturn(12345);

      final httpClient = MockHttpClient();
      when(() => httpClient.close(force: true)).thenReturn(null);

      final subscription = MockStreamSubscription();
      when(() => subscription.cancel()).thenAnswer((_) => Future.value());

      final timer = MockTimer();
      when(() => timer.cancel()).thenReturn(null);

      CleanupUtils.registerResource('multi-resource-job', process);
      CleanupUtils.registerResource('multi-resource-job', httpClient);
      CleanupUtils.registerResource('multi-resource-job', subscription);
      CleanupUtils.registerResource('multi-resource-job', timer);

      await CleanupUtils.cleanupJobResources('multi-resource-job');

      verify(() => process.kill(ProcessSignal.sigkill)).called(1);
      verify(() => httpClient.close(force: true)).called(1);
      verify(() => subscription.cancel()).called(1);
      verify(() => timer.cancel()).called(1);

      expect(token.isCancelled, isTrue);
    });

    test('cleanupJobResources silently handles unregistered job', () async {
      // Should not throw
      await expectLater(
          CleanupUtils.cleanupJobResources('unknown-job'), completes);
    });

    test('emergencyCleanup cleans all registered jobs', () async {
      final token1 = CancelToken();
      final token2 = CancelToken();

      CleanupUtils.registerJob('job-1', token1);
      CleanupUtils.registerJob('job-2', token2);

      final process1 = MockProcess();
      when(() => process1.kill(any())).thenReturn(true);
      when(() => process1.pid).thenReturn(111);

      final process2 = MockProcess();
      when(() => process2.kill(any())).thenReturn(true);
      when(() => process2.pid).thenReturn(222);

      CleanupUtils.registerResource('job-1', process1);
      CleanupUtils.registerResource('job-2', process2);

      await CleanupUtils.emergencyCleanup();

      verify(() => process1.kill(ProcessSignal.sigkill)).called(1);
      verify(() => process2.kill(ProcessSignal.sigkill)).called(1);

      expect(token1.isCancelled, isTrue);
      expect(token2.isCancelled, isTrue);
    });

    test('registerResource handles job that is not registered', () async {
      final process = MockProcess();
      // Should not throw, and should not add to any list
      CleanupUtils.registerResource('unregistered-job', process);

      // Cleanup the job, shouldn't call kill on the process
      await CleanupUtils.cleanupJobResources('unregistered-job');

      verifyNever(() => process.kill(any()));
    });

    test('handles exceptions during resource disposal gracefully', () async {
      final token = CancelToken();
      CleanupUtils.registerJob('exception-job', token);

      final process = MockProcess();
      // Simulate an exception when killing the process
      when(() => process.kill(any()))
          .thenThrow(Exception('Failed to kill process'));
      when(() => process.pid).thenReturn(555);

      final httpClient = MockHttpClient();
      when(() => httpClient.close(force: true)).thenReturn(null);

      CleanupUtils.registerResource('exception-job', process);
      CleanupUtils.registerResource('exception-job', httpClient);

      // Should complete normally without throwing, and still process the httpClient
      await expectLater(
          CleanupUtils.cleanupJobResources('exception-job'), completes);

      verify(() => process.kill(ProcessSignal.sigkill)).called(1);
      verify(() => httpClient.close(force: true))
          .called(1); // Next resource still processed
      expect(token.isCancelled, isTrue);
    });
  });
}
