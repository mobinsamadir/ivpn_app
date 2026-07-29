import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/endpoints.dart';

void main() {
  group('Endpoints Tests', () {
    test('TestEndpoints properties return expected values', () {
      expect(TestEndpoints.pingEndpoints, isNotEmpty);
      expect(TestEndpoints.pingEndpoints.length, 4);
      expect(TestEndpoints.speedSmall, [adaptiveSpeedTestEndpoints[0]]);
      expect(TestEndpoints.speedMedium, [adaptiveSpeedTestEndpoints[1]]);
      expect(TestEndpoints.speedLarge, [adaptiveSpeedTestEndpoints[2]]);
    });

    test('adaptiveSpeedTestEndpoints contains valid URLs', () {
      expect(adaptiveSpeedTestEndpoints.length, 5);
      expect(adaptiveSpeedTestEndpoints[0], 'https://httpbin.org/bytes/100000');
    });
  });
}
