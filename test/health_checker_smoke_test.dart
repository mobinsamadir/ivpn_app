import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/testers/health_checker.dart';
import 'package:ivpn_new/models/testing/test_results.dart';

void main() {
  test('AdvancedHealthChecker initializes correctly', () {
    final checker = AdvancedHealthChecker(httpPort: 8080);
    expect(checker.httpPort, 8080);
  });

  test('HealthMetrics empty factory works', () {
    final metrics = HealthMetrics.empty();
    expect(metrics.averageLatency, -1);
    expect(metrics.successRate, 0);
  });
}
