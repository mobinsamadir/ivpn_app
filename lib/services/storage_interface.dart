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
