import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/testers/ephemeral_tester.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EphemeralTester process tests', () {
    test('runTest fails safely on invalid port or non-existent binary',
        () async {
      final tester = EphemeralTester();

      final config = VpnConfigWithMetrics.fromJson({
        'id': 'test',
        'rawConfig': 'vless://uuid@127.0.0.1:443',
      });

      final result = await tester.runTest(config);

      expect(result.ping, equals(-1));
    });
  });
}
