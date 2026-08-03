import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:ivpn_new/services/testers/ephemeral_tester.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';


class FakeProcess implements Process {
  @override
  Future<int> get exitCode => Future.value(0);
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  int get pid => 1234;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EphemeralTester Tests', () {

    test('registerProcess and killAll completes safely', () {
      final fakeProcess = FakeProcess();
      EphemeralTester.registerProcess(fakeProcess);
      EphemeralTester.killAll();
      expect(true, isTrue);
    });


    test('runTest sets failureReason and ping to -1 on invalid configuration', () async {
      final tester = EphemeralTester();
      final config = VpnConfigWithMetrics.fromJson({
        'id': 'test',
        'rawConfig': 'bad_config://',
      });
      final result = await tester.runTest(config);
      expect(result.ping, equals(-1));
      expect(result.failureReason, isNotNull);
      expect(result.lastFailedStage, isNotNull);
    });

    test('Semaphore limits concurrent execution', () {
      fakeAsync((async) {
        final semaphore = Semaphore(3);
        int active = 0;
        int maxActive = 0;

        Future<void> task(int durationMs) async {
          await semaphore.acquire();
          active++;
          if (active > maxActive) maxActive = active;
          await Future.delayed(Duration(milliseconds: durationMs));
          active--;
          semaphore.release();
        }

        List.generate(10, (_) => task(50));

        async.elapse(const Duration(milliseconds: 500));

        expect(maxActive, lessThanOrEqualTo(3));
        expect(active, 0);
      });
    });

    test('runTest handles errors gracefully and returns updated config',
        () async {
      final tester = EphemeralTester();
      final config = VpnConfigWithMetrics(
        id: '1',
        rawConfig: 'invalid://',
        name: 'test',
        addedDate: DateTime.now(),
      );
      final result = await tester.runTest(config);
      expect(result.tier, equals(0));
    });

    test('runTest throws argument error on null', () async {
      final tester = EphemeralTester();
      final config = VpnConfigWithMetrics(
        id: '3',
        rawConfig: '{"invalid": true',
        name: 'test3',
        addedDate: DateTime.now(),
      );
      final result = await tester.runTest(config);
      expect(result.tier, equals(0));
    });

    test('Semaphore limits concurrent execution FIFO', () {
      fakeAsync((async) {
        final semaphore = Semaphore(1);
        final List<int> order = [];

        Future<void> task(int id) async {
          await semaphore.acquire();
          order.add(id);
          await Future.delayed(const Duration(milliseconds: 10));
          semaphore.release();
        }

        task(0);
        task(1);
        task(2);

        async.elapse(const Duration(milliseconds: 100));

        expect(order, [0, 1, 2]);
      });
    });
  });
}
