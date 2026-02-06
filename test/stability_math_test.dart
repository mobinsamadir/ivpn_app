import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/chart_utils.dart';

void main() {
  group('ChartUtils Tests', () {
    test('calculateJitter should return 0 for empty list', () {
      expect(ChartUtils.calculateJitter([]), 0.0);
    });

    test('calculateJitter should return 0 for single sample', () {
      expect(ChartUtils.calculateJitter([100]), 0.0);
    });

    test('calculateJitter should calculate average difference correctly', () {
      // Differences: |110-100|=10, |100-110|=10, |120-100|=20. Total: 40. Count: 3. Avg: 13.33
      final samples = [100, 110, 100, 120];
      expect(ChartUtils.calculateJitter(samples), closeTo(13.33, 0.01));
    });

    test('calculateJitter should ignore -1 values', () {
      final samples = [100, -1, 110, -1, 100];
      // Valid samples: [100, 110, 100]. Differences: |110-100|=10, |100-110|=10. Total: 20. Count: 2. Avg: 10.0
      expect(ChartUtils.calculateJitter(samples), 10.0);
    });

    test('calculateStandardDeviation should calculate correctly', () {
      final samples = [10, 10, 10, 10];
      expect(ChartUtils.calculateStandardDeviation(samples), 0.0);
      
      final samples2 = [10, 20]; // Mean: 15. Variance: ((10-15)^2 + (20-15)^2)/2 = (25+25)/2 = 25. SD: 5.0
      expect(ChartUtils.calculateStandardDeviation(samples2), 5.0);
    });
  });
}
