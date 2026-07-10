import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:ivpn_new/services/testers/ephemeral_tester.dart';

void main() {
  group('Semaphore Tests', () {
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

        final tasks = List.generate(10, (_) => task(50));

        async.elapse(const Duration(milliseconds: 500));

        // At this point, the wait should complete inside fakeAsync
        expect(maxActive, lessThanOrEqualTo(3));
        expect(active, 0);
      });
    });

    test('Semaphore processes tasks in order (FIFO)', () {
      fakeAsync((async) {
        final semaphore = Semaphore(1);
        final List<int> order = [];

        Future<void> task(int id) async {
          await semaphore.acquire();
          order.add(id);
          await Future.delayed(const Duration(milliseconds: 10));
          semaphore.release();
        }

        // Fire tasks 0, 1, 2, 3, 4
        task(0);
        task(1);
        task(2);
        task(3);
        task(4);

        async.elapse(const Duration(milliseconds: 100));

        expect(order, [0, 1, 2, 3, 4]);
      });
    });
  });
}
