import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class StorageInterface {
  Future<String?> getString(String key);
  Future<bool> setString(String key, String value);
  Future<bool?> getBool(String key);
  Future<bool> setBool(String key, bool value);
  Future<bool> remove(String key);
}

class SharedPreferencesStorage implements StorageInterface {
  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  Future<String?> getString(String key) async {
    final prefs = await _getPrefs();
    return prefs.getString(key);
  }

  @override
  Future<bool> setString(String key, String value) async {
    final prefs = await _getPrefs();
    return prefs.setString(key, value);
  }

  @override
  Future<bool?> getBool(String key) async {
    final prefs = await _getPrefs();
    return prefs.getBool(key);
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    final prefs = await _getPrefs();
    return prefs.setBool(key, value);
  }

  @override
  Future<bool> remove(String key) async {
    final prefs = await _getPrefs();
    return prefs.remove(key);
  }
}



class SecureStorage implements StorageInterface {
  final _secureStorage = const FlutterSecureStorage();

  @override
  Future<String?> getString(String key) async {
    return _secureStorage.read(key: key);
  }

  @override
  Future<bool> setString(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
    return true; // write returns void
  }

  @override
  Future<bool?> getBool(String key) async {
    final str = await _secureStorage.read(key: key);
    if (str == null) return null;
    return str.toLowerCase() == 'true';
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
