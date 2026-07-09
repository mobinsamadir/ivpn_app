import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';

// Create an abstract interface to allow mocking the function type
abstract class ProcessRunner {
  Future<ProcessResult> run(String executable, List<String> arguments);
}

class MockProcessRunner extends Mock implements ProcessRunner {}

class MockFile implements File {
  final String _path;
  final bool _exists;
  final bool _throwException;

  MockFile(this._path, {bool exists = false, bool throwException = false})
      : _exists = exists,
        _throwException = throwException;

  @override
  String get path => _path;

  @override
  bool existsSync() {
    if (_throwException) {
      throw const FileSystemException(
          'Permission denied', 'path/to/file', OSError('Access is denied.', 5));
    }
    return _exists;
  }

  @override
  Future<bool> exists() async {
    return existsSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  group('WindowsVpnService.checkRequiredAssets', () {
    test('returns false when files do not exist', () async {
      await IOOverrides.runZoned(
        () async {
          final service = WindowsVpnService();
          final result = await service.checkRequiredAssets();
          expect(result, isFalse);
        },
        createFile: (path) => MockFile(path, exists: false),
      );
    });

    test('returns false when only some files exist', () async {
      await IOOverrides.runZoned(
        () async {
          final service = WindowsVpnService();
          final result = await service.checkRequiredAssets();
          expect(result, isFalse);
        },
        createFile: (path) {
          // Only return true for sing-box.exe to test failure on geoip.db/geosite.db
          return MockFile(path, exists: path.contains('sing-box.exe'));
        },
      );
    });

    test(
        'returns false when a FileSystemException is thrown (Permission Error)',
        () async {
      await IOOverrides.runZoned(
        () async {
          final service = WindowsVpnService();
          final result = await service.checkRequiredAssets();
          expect(result, isFalse);
        },
        createFile: (path) => MockFile(path, throwException: true),
      );
    });

    test('returns true when files exist', () async {
      await IOOverrides.runZoned(
        () async {
          final service = WindowsVpnService();
          final result = await service.checkRequiredAssets();
          expect(result, isTrue);
        },
        createFile: (path) => MockFile(path, exists: true),
      );
    });
  });
}
