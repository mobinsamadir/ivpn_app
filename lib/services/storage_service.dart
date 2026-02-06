// lib/services/storage_service.dart

import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_model.dart';

class StorageService {
  final SharedPreferences _prefs;

  // کلیدهای ذخیره‌سازی
  static const _serversKey = 'saved_servers';
  static const _lastUpdateKey = 'last_update_timestamp';
  static const _recentServersKey =
      'recent_servers_list'; // <-- کلید برای سرورهای اخیر
  static const _favoriteIdsKey = 'favorite_server_ids';
  static const _theBestIdsKey = 'the_best_server_ids';
  static const _obsoleteIdsKey = 'obsolete_server_ids';

  StorageService({required SharedPreferences prefs}) : _prefs = prefs;

  // --- متدهای ذخیره‌سازی ---
  Future<void> saveServers(List<Server> servers) async {
    final serverConfigs = servers.map((s) => s.rawConfig).toList();
    await _prefs.setStringList(_serversKey, serverConfigs);
  }

  // متد بازگردانده شده برای ذخیره سرورهای اخیر
  Future<void> saveRecentServers(List<Server> servers) async {
    final serverConfigs = servers.map((s) => s.rawConfig).toList();
    await _prefs.setStringList(_recentServersKey, serverConfigs);
  }

  Future<void> saveFavoriteIds(List<String> ids) async {
    await _prefs.setStringList(_favoriteIdsKey, ids);
  }

  Future<void> saveTheBestIds(List<String> ids) async {
    await _prefs.setStringList(_theBestIdsKey, ids);
  }

  Future<void> saveObsoleteIds(List<String> ids) async {
    await _prefs.setStringList(_obsoleteIdsKey, ids);
  }

  Future<void> saveLastUpdateTimestamp() async {
    await _prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());
  }

  // --- متدهای بازیابی ---
  Future<List<Server>> loadServers() async {
    final serverConfigs = _prefs.getStringList(_serversKey) ?? [];
    return serverConfigs
        .map((config) => Server.fromConfigString(config))
        .whereType<Server>()
        .toList();
  }

  // متد بازگردانده شده برای بازیابی سرورهای اخیر
  Future<List<Server>> loadRecentServers() async {
    final serverConfigs = _prefs.getStringList(_recentServersKey) ?? [];
    return serverConfigs
        .map((config) => Server.fromConfigString(config))
        .whereType<Server>()
        .toList();
  }

  Future<List<String>> loadFavoriteIds() async {
    return _prefs.getStringList(_favoriteIdsKey) ?? [];
  }

  Future<List<String>> loadTheBestIds() async {
    return _prefs.getStringList(_theBestIdsKey) ?? [];
  }

  Future<List<String>> loadObsoleteIds() async {
    return _prefs.getStringList(_obsoleteIdsKey) ?? [];
  }

  Future<DateTime?> getLastUpdateTimestamp() async {
    final timestampStr = _prefs.getString(_lastUpdateKey);
    return timestampStr != null ? DateTime.parse(timestampStr) : null;
  }
}
