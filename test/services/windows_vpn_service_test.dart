import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';
import 'dart:async';

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
        'Permission denied',
        'path/to/file',
        OSError('Access is denied.', 5),
      );
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
  group('WindowsVpnService.checkRequiredAssets', () {
    test('returns false when files do not exist', () async {
      await IOOverrides.runZoned(() async {
        final service = WindowsVpnService();
        final result = await service.checkRequiredAssets();
        expect(result, isFalse);
      }, createFile: (path) => MockFile(path, exists: false));
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
        await IOOverrides.runZoned(() async {
          final service = WindowsVpnService();
          final result = await service.checkRequiredAssets();
          expect(result, isFalse);
        }, createFile: (path) => MockFile(path, throwException: true));
      },
    );

    test('returns true when files exist', () async {
      await IOOverrides.runZoned(() async {
        final service = WindowsVpnService();
        final result = await service.checkRequiredAssets();
        expect(result, isTrue);
      }, createFile: (path) => MockFile(path, exists: true));
    });
  });

  group('WindowsVpnService Basic Methods', () {
    late WindowsVpnService service;

    setUp(() {
      service = WindowsVpnService();
    });

    test('isUserInitiatedDisconnect is updated statically', () {
      WindowsVpnService.isUserInitiatedDisconnect = true;
      expect(WindowsVpnService.isUserInitiatedDisconnect, isTrue);
    });

    test('Streams exist', () {
      expect(service.statusStream, isA<Stream<String>>());
      expect(service.logStream, isA<Stream<String>>());
    });

    test('stopVpn handles disconnected state gracefully', () async {
      await expectLater(service.stopVpn(), completes);
    });
          });

  group('WindowsVpnService.getExecutablePath', () {
    test('finds executable in local path', () async {
      final expectedLocalPath = p.join(
        Directory.current.path,
        'assets',
        'executables',
        'windows',
        'sing-box.exe',
      );
      await IOOverrides.runZoned(() async {
        final path = await WindowsVpnService.getExecutablePath();
        expect(path, expectedLocalPath);
      }, createFile: (path) => MockFile(path, exists: path == expectedLocalPath));
    });

    test('finds executable in bundled path', () async {
       final exeDir = p.dirname(Platform.resolvedExecutable);
       final expectedBundledPath = p.join(
         exeDir,
         'data',
         'flutter_assets',
         'assets',
         'executables',
         'windows',
         'sing-box.exe',
       );

       await IOOverrides.runZoned(() async {
        final path = await WindowsVpnService.getExecutablePath();
        expect(path, expectedBundledPath);
      }, createFile: (path) => MockFile(path, exists: path == expectedBundledPath));
    });
  });
}
