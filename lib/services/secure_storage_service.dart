import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'storage_interface.dart';

class SecureStorageService implements StorageInterface {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  Future<String?> getString(String key) async {
    return await _secureStorage.read(key: key);
  }

  @override
  Future<bool> setString(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
    return true; // write doesn't return a boolean, assuming success
  }

  @override
  Future<bool?> getBool(String key) async {
    final value = await _secureStorage.read(key: key);
    if (value == null) return null;
    return value.toLowerCase() == 'true';
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    await _secureStorage.write(key: key, value: value.toString());
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    await _secureStorage.delete(key: key);
    return true;
  }
}
