import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/testers/adaptive_speed_tester.dart';
import 'package:ivpn_new/utils/cancellable_operation.dart';

void main() {
  group('Adaptive Speed Test Diagnostic', () {
    late AdaptiveSpeedTester tester;
    
    setUp(() {
      tester = AdaptiveSpeedTester();
    });
    
    tearDown(() {
      // Cleanup
    });
    
    test('Test empty endpoints list', () async {
      final result = await tester.runAdaptiveTest([], config: "");
      expect(result.downloadMbps, 0.0);
    });
    
    test('Test with fast endpoint', () async {
      final result = await tester.runAdaptiveTest([
        'http://httpbin.org/bytes/102400', // 100KB
      ], config: "");
      print('Speed result: ${result.downloadMbps} Mbps');
      expect(result.downloadMbps, greaterThanOrEqualTo(0.0));
    });
    
    test('Test cancellation', () async {
      final cancelToken = CancelToken();
      final future = tester.runAdaptiveTest(
        ['http://httpbin.org/delay/10'],
        cancelToken: cancelToken,
        config: "",
      );
      
      // Cancel after 500ms
      await Future.delayed(const Duration(milliseconds: 500));
      cancelToken.cancel();
      
      final result = await future;
      expect(result.downloadMbps, 0.0);
    });
    
    test('Test multiple endpoints', () async {
      final result = await tester.runAdaptiveTest([
        'http://httpbin.org/bytes/51200',
        'http://httpbin.org/bytes/102400',
        'http://httpbin.org/bytes/204800',
      ], config: "");
      print('Multiple endpoints result: ${result.downloadMbps} Mbps');
      expect(result.downloadMbps, greaterThanOrEqualTo(0.0));
    });
  });
}
