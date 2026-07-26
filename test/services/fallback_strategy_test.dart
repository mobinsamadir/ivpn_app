import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/fallback_strategy.dart';
import 'package:ivpn_new/services/test_job.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';

void main() {
  group('TestFallbackStrategy Tests', () {
    test('triggerFallback does not throw error for speed test', () {
      final token = CancelToken();
      expect(
        () => TestFallbackStrategy.triggerFallback(TestType.speed, '123', token),
        returnsNormally,
      );
    });

    test('triggerFallback does not throw error for health test', () {
      final token = CancelToken();
      expect(
        () => TestFallbackStrategy.triggerFallback(TestType.health, '123', token),
        returnsNormally,
      );
    });
  });
}
