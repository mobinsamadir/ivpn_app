import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/test_job.dart';

void main() {
  group('TestJob', () {
    test('creates and stringifies correctly', () {
      final job = TestJob(
        type: TestType.ping,
        task: () async {},
        name: 'MyPingJob',
      );

      expect(job.name, 'MyPingJob');
      expect(job.type, TestType.ping);
      expect(job.toString(), contains('MyPingJob'));
      expect(job.toString(), contains('TestType.ping'));
    });
  });
}
