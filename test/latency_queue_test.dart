import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/latency_service.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';

class FakeWindowsVpnService extends WindowsVpnService {
  @override
  Future<String> getExecutablePath() async => "fake_xray.exe";
  
  @override
  String generateConfig(String rawLink, {int socksPort = 10808, int httpPort = 10809}) => "{}";
}

void main() {
  group('LatencyService Unit Tests', () {
    test('Sequential Processing: Should process requests in order', () async {
      final vpnService = FakeWindowsVpnService();
      final service = LatencyService(vpnService);

      // This test mainly verifies that getLatency doesn't throw and handles the queue.
      // Since we uses Fake service, the actual process start will fail, but LatencyService 
      // should catch it and return -1.
      
      final f1 = service.getLatency("vmess://eyJhZGQiOiIxMjcuMC4wLjEiLCJwb3J0IjoiMSIsImlkIjoidXVpZCJ9");
      final f2 = service.getLatency("vmess://eyJhZGQiOiIxMjcuMC4wLjEiLCJwb3J0IjoiMiIsImlkIjoidXVpZCJ9");
      
      final r1 = await f1;
      final r2 = await f2;

      expect(r1, equals(-1)); // Fails because fake_xray.exe doesn't exist
      expect(r2, equals(-1));
    });

    test('TCP Pre-check: Should fail fast (500ms) on closed port', () async {
      final vpnService = FakeWindowsVpnService();
      final service = LatencyService(vpnService);

      final stopwatch = Stopwatch()..start();
      // Use a port that is very likely to be closed
      final result = await service.getLatency("vmess://eyJhZGQiOiIxMjcuMC4wLjEiLCJwb3J0IjoiNTk5OTkiLCJpZCI6InV1aWQifQ==");
      stopwatch.stop();

      expect(result, equals(-1));
      // Pre-check timeout is 500ms. Allow some OS overhead.
      expect(stopwatch.elapsedMilliseconds, isBelow(1000));
    });
  });
}

Matcher isBelow(int value) => _IsBelow(value);

class _IsBelow extends Matcher {
  final int _value;
  _IsBelow(this._value);
  @override
  Description describe(Description description) => description.add('is below $_value');
  @override
  bool matches(item, Map matchState) => item < _value;
}
