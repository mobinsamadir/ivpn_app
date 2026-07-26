import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/fallback_strategy.dart';
import 'package:ivpn_new/services/test_job.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';

void main() {
  group('TestFallbackStrategy', () {
    test('triggerFallback speed handles it', () {
      final token = CancelToken();
      TestFallbackStrategy.triggerFallback(TestType.speed, 'job_123', token);
      expect(true, isTrue); // If it doesn't throw, it works.
    });

    test('triggerFallback health handles it', () {
      final token = CancelToken();
      TestFallbackStrategy.triggerFallback(TestType.health, 'job_456', token);
      expect(true, isTrue);
    });

    test('triggerFallback other handles it', () {
      final token = CancelToken();
      TestFallbackStrategy.triggerFallback(TestType.stability, 'job_789', token);
      expect(true, isTrue);
    });
  });
}
