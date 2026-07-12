import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';

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
}
