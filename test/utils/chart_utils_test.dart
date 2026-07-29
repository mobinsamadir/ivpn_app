import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/chart_utils.dart';

void main() {
  group('ChartUtils Tests', () {
    test('calculateJitter returns 0 for empty or single sample list', () {
      expect(ChartUtils.calculateJitter([]), 0.0);
      expect(ChartUtils.calculateJitter([1]), 0.0);
    });

    test('calculateJitter calculates jitter correctly', () {
      expect(ChartUtils.calculateJitter([10, 20, 10]), 10.0);
      expect(ChartUtils.calculateJitter([10, 15, 20]), 5.0);
    });

    test('calculateJitter ignores negative or zero samples', () {
      expect(ChartUtils.calculateJitter([10, -5, 0, 20, 10]), 10.0);
    });

    test(
        'calculateStandardDeviation returns 0 for empty or all non-positive samples',
        () {
      expect(ChartUtils.calculateStandardDeviation([]), 0.0);
      expect(ChartUtils.calculateStandardDeviation([-1, 0, -2]), 0.0);
    });

    test('calculateStandardDeviation calculates std dev correctly', () {
      // Valid samples: 2, 4, 4, 4, 5, 5, 7, 9 -> mean = 5. std dev = 2
      expect(
          ChartUtils.calculateStandardDeviation([2, 4, 4, 4, 5, 5, 7, 9]), 2.0);
    });

    test('calculateStandardDeviation ignores negative or zero samples', () {
      // Valid samples: 2, 4, 4, 4, 5, 5, 7, 9
      expect(
          ChartUtils.calculateStandardDeviation(
              [2, -1, 4, 0, 4, 4, 5, -5, 5, 7, 9]),
          2.0);
    });

    test('calculateMovingAverage returns empty list for empty input', () {
      expect(ChartUtils.calculateMovingAverage([], 3), []);
    });

    test('calculateMovingAverage calculates moving average correctly', () {
      final samples = [10, 20, 30, 40, 50];
      expect(ChartUtils.calculateMovingAverage(samples, 3),
          [10.0, 15.0, 20.0, 30.0, 40.0]);
    });

    test('calculateMovingAverage ignores negative or zero samples', () {
      final samples = [10, -5, 20, 0, 30];
      expect(ChartUtils.calculateMovingAverage(samples, 3),
          [10.0, 10.0, 15.0, 20.0, 25.0]);
    });
  });
}
