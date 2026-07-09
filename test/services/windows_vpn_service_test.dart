import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';

// Create an abstract interface to allow mocking the function type
abstract class ProcessRunner {
  Future<ProcessResult> run(String executable, List<String> arguments);
}

class MockProcessRunner extends Mock implements ProcessRunner {}

void main() {
  group('WindowsVpnService Tests', () {
    late WindowsVpnService service;
    late MockProcessRunner mockRunner;

    setUp(() {
      service = WindowsVpnService();
      mockRunner = MockProcessRunner();
    });

    test('forceKillSingBoxProcessesForTesting executes taskkill successfully',
        () async {
      when(() => mockRunner.run('taskkill', ['/F', '/IM', 'sing-box.exe']))
          .thenAnswer((_) async => ProcessResult(123, 0, 'Killed', ''));

      await service.forceKillSingBoxProcessesForTesting(
        processRunner: mockRunner.run,
        isWindowsOverride: true,
      );

      verify(() => mockRunner.run('taskkill', ['/F', '/IM', 'sing-box.exe']))
          .called(1);
    });

    test('forceKillSingBoxProcessesForTesting handles process not found',
        () async {
      when(() => mockRunner.run('taskkill', ['/F', '/IM', 'sing-box.exe']))
          .thenAnswer((_) async => ProcessResult(
              123, 128, '', 'ERROR: The process "sing-box.exe" not found.'));

      await service.forceKillSingBoxProcessesForTesting(
        processRunner: mockRunner.run,
        isWindowsOverride: true,
      );

      verify(() => mockRunner.run('taskkill', ['/F', '/IM', 'sing-box.exe']))
          .called(1);
    });

    test('forceKillSingBoxProcessesForTesting catches and ignores exceptions',
        () async {
      when(() => mockRunner.run('taskkill', ['/F', '/IM', 'sing-box.exe']))
          .thenThrow(const ProcessException('taskkill', []));

      // Should not throw
      await service.forceKillSingBoxProcessesForTesting(
        processRunner: mockRunner.run,
        isWindowsOverride: true,
      );

      verify(() => mockRunner.run('taskkill', ['/F', '/IM', 'sing-box.exe']))
          .called(1);
    });

    test('forceKillSingBoxProcessesForTesting skips execution if not Windows',
        () async {
      await service.forceKillSingBoxProcessesForTesting(
        processRunner: mockRunner.run,
        isWindowsOverride: false,
      );

      verifyNever(() => mockRunner.run(any(), any()));
    });
  });
}
