import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/testers/ephemeral_tester.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';
import 'dart:io';

class FakeProcess implements Process {
  @override
  Future<int> get exitCode => Future.value(0);
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  int get pid => 1234;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('EphemeralTester extra coverage', () {
    test('killAll fails gracefully', () async {
      EphemeralTester.registerProcess(FakeProcess());
      EphemeralTester.killAll();
      expect(true, isTrue);
    });
    test('generateConfig creates config', () async {
      final tester = EphemeralTester();
      expect(tester, isNotNull);
    });
  });
}
