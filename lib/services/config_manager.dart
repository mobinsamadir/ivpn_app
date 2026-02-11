import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';
import '../models/vpn_config_with_metrics.dart';
import '../utils/advanced_logger.dart';

class ConfigManager extends ChangeNotifier {
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();

  // --- STATE VARIABLES ---
  List<VpnConfigWithMetrics> allConfigs = [];
  List<VpnConfigWithMetrics> validatedConfigs = [];
  List<VpnConfigWithMetrics> favoriteConfigs = [];

  String _currentDeviceId = 'unknown';
  String get currentDeviceId => _currentDeviceId;

  VpnConfigWithMetrics? _selectedConfig;
  VpnConfigWithMetrics? get selectedConfig => _selectedConfig;

  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  String _connectionStatus = 'Ready';
  String get connectionStatus => _connectionStatus;

  Timer? _sessionTimer;
  Timer? _throttleTimer; // For UI throttling
  bool _hasPendingUpdates = false; // Flag for buffered updates

  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  bool _isAutoSwitchEnabled = true;
  bool get isAutoSwitchEnabled => _isAutoSwitchEnabled;
  set isAutoSwitchEnabled(bool value) {
    _isAutoSwitchEnabled = value;
    _saveAutoSwitchSetting();
    notifyListeners();
  }

  // --- CONSTANTS ---
  static const String _configsKey = 'vpn_configs';
  static const String _autoSwitchKey = 'auto_switch_enabled';

  // --- INITIALIZATION ---
  Future<void> init() async {
    AdvancedLogger.info('[ConfigManager] Initializing...');
    await _initDeviceId();
    await _loadAutoSwitchSetting();
    await _loadConfigs();
    _updateListsSync();
    AdvancedLogger.info('[ConfigManager] Initialization complete. Loaded ${allConfigs.length} configs.');
  }

  // --- CORE: FETCH & PARSE ---
  Future<bool> fetchStartupConfigs() async {
    if (_isRefreshing) return false;
    _isRefreshing = true;
    notifyListeners();

    bool anyConfigAdded = false;

    try {
      AdvancedLogger.info('[ConfigManager] Downloading configs from mirrors...');
      
      // Mirrors List (GitHub -> Gist -> MyFiles -> Drive API)
      final mirrors = [
        'https://raw.githubusercontent.com/yebekhe/TelegramV2rayCollector/main/sub/normal/mix',
        'https://raw.githubusercontent.com/mobinsamadir/ivpn-servers/refs/heads/main/servers.txt',
        'https://gist.githubusercontent.com/mobinsamadir/687a7ef199d6eaf6d1912e36151a9327/raw/servers.txt',
        'https://my.files.ir/drive/s/D7zxAbnxHc4y4353UkL2RZ21MrjxJz',
        'https://drive.google.com/uc?export=download&id=1S7CI5xq4bbnERZ1i1eGuYn5bhluh2LaW',
      ];

      for (final url in mirrors) {
        if (anyConfigAdded) break; // Chain Breaking: Stop if we already have configs

        try {
          AdvancedLogger.info('[ConfigManager] Attempting fetch from: $url');
          
          final response = await http.get(
            Uri.parse(url),
            headers: {
              "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
              "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
              "Accept-Language": "en-US,en;q=0.5",
            },
          ).timeout(const Duration(seconds: 30));
          
          if (response.statusCode == 200) {
            String content = response.body;
            AdvancedLogger.info('✅ Downloaded ${content.length} bytes successfully from $url.');

            // 1. Parse Mixed Content (Configs ONLY - No Recursion)
            final configUrls = await parseMixedContent(content);

            if (configUrls.isNotEmpty) {
               // 2. SANITIZE: Remove malicious fields
               final cleanedConfigs = configUrls.map((c) {
                 return c.replaceAll(RegExp(r'"spider_x":\s*("[^"]*"|[^,{}]+),?'), '');
               }).toList();

               // 3. Add to Database
               int added = await addConfigs(cleanedConfigs);
               if (added > 0) {
                  AdvancedLogger.info('[ConfigManager] Import finished: Added $added new configs from $url.');
                  anyConfigAdded = true;
               } else {
                  AdvancedLogger.warn('[ConfigManager] Configs found but were duplicates/invalid.');
               }
            } else {
               AdvancedLogger.warn('[ConfigManager] No valid configs found in content from $url.');
            }

          } else {
             AdvancedLogger.warn('[ConfigManager] HTTP Error ${response.statusCode} from $url');
          }
        } catch (e) {
          AdvancedLogger.warn('[ConfigManager] Failed to fetch from $url: $e');
        }
      }

      if (!anyConfigAdded) {
        AdvancedLogger.error('[ConfigManager] All attempts to fetch configs failed or yielded 0 new configs.');
      }

    } catch (e) {
       AdvancedLogger.error('[ConfigManager] Critical error in fetchStartupConfigs: $e');
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }

    return anyConfigAdded;
  }

  // --- SMART PARSER (Regex Extraction Only - NO Recursion) ---
  static Future<List<String>> parseMixedContent(String text) async {
    final collectedConfigs = <String>{};
    
    String processedText = text;
    // Try Base64 Decode first
    try {
      final decoded = utf8.decode(base64Decode(text.replaceAll(RegExp(r'\s+'), '')));
      // Check if decoded content looks promising
      if (decoded.contains('://')) processedText = decoded;
    } catch (e) {
      // Not base64 or decode failed, treat as raw text
    }

    // Extract Standard Configs
    final regex = RegExp(
      r'(vless|vmess|trojan|ss):\/\/[a-zA-Z0-9%?=&-._#@:\[\]]+',
      caseSensitive: false,
      multiLine: true,
    );
    
    for (final match in regex.allMatches(processedText)) {
       final config = match.group(0);
       if (config != null) collectedConfigs.add(config.trim());
    }

    // NO Recursion: We do NOT fetch links anymore.
    
    return collectedConfigs.toList();
  }

  // --- THROTTLING LOGIC ---
  void notifyListenersThrottled() {
    if (_throttleTimer?.isActive ?? false) {
      _hasPendingUpdates = true;
      return;
    }

    _throttleTimer = Timer(const Duration(milliseconds: 500), _onThrottleTick);
  }

  void _onThrottleTick() {
    _updateListsSync(); // Sync update to avoid race conditions
    notifyListeners();

    _throttleTimer = null;

    // If updates accumulated while waiting, trigger another cycle immediately
    if (_hasPendingUpdates) {
      _hasPendingUpdates = false;
      notifyListenersThrottled();
    }
  }

  // --- DATABASE OPERATIONS ---
  Future<int> addConfigs(List<String> configStrings) async {
    int addedCount = 0;
    
    // Use Set for faster lookup of existing configs
    final existingConfigs = allConfigs.map((c) => c.rawConfig.trim()).toSet();
    
    for (final raw in configStrings) {
      final trimmedRaw = raw.trim();
      if (trimmedRaw.isEmpty || existingConfigs.contains(trimmedRaw)) continue;

      final name = _extractServerName(trimmedRaw);
      final id = 'config_${DateTime.now().millisecondsSinceEpoch}_$addedCount';

      allConfigs.add(VpnConfigWithMetrics(
        id: id,
        rawConfig: trimmedRaw,
        name: name,
        countryCode: _extractCountryCode(name),
      ));
      
      existingConfigs.add(trimmedRaw);
      addedCount++;
    }

    if (addedCount > 0) {
      _updateListsSync();
      await _saveAllConfigs();
      notifyListeners();
    }
    return addedCount;
  }

  Future<void> updateConfigMetrics(String id, {int? ping, double? speed, bool? connectionSuccess}) async {
     final index = allConfigs.indexWhere((c) => c.id == id);
     if (index != -1) {
        // Update in-place
        allConfigs[index] = allConfigs[index].updateMetrics(
           deviceId: _currentDeviceId,
           ping: ping, 
           speed: speed, 
           connectionSuccess: connectionSuccess ?? false
        );
        // Don't sort immediately, use throttling
        notifyListenersThrottled();
     }
  }

  Future<void> updateConfigDirectly(VpnConfigWithMetrics config) async {
     final index = allConfigs.indexWhere((c) => c.id == config.id);
     if (index != -1) {
        allConfigs[index] = config;
     }
     // Don't sort immediately, use throttling
     notifyListenersThrottled();
  }
  
  Future<void> markSuccess(String id) async {
      final index = allConfigs.indexWhere((c) => c.id == id);
      if (index != -1) {
         allConfigs[index] = allConfigs[index].copyWith(
            failureCount: 0,
            lastSuccessfulConnectionTime: DateTime.now().millisecondsSinceEpoch,
            isAlive: true
         );
         _updateListsSync();
         await _saveAllConfigs();
         notifyListeners();
      }
  }
  
  Future<void> markFailure(String id) async {
      final index = allConfigs.indexWhere((c) => c.id == id);
      if (index != -1) {
         allConfigs[index] = allConfigs[index].copyWith(
            failureCount: allConfigs[index].failureCount + 1,
            isAlive: false
         );
         _updateListsSync();
         await _saveAllConfigs();
         notifyListeners();
      }
  }

  Future<bool> deleteConfig(String id) async {
     allConfigs.removeWhere((c) => c.id == id);
     if (_selectedConfig?.id == id) _selectedConfig = null;
     _updateListsSync();
     await _saveAllConfigs();
     notifyListeners();
     return true;
  }
  
  Future<void> toggleFavorite(String id) async {
      final index = allConfigs.indexWhere((c) => c.id == id);
      if (index != -1) {
         allConfigs[index] = allConfigs[index].copyWith(
            isFavorite: !allConfigs[index].isFavorite
         );
         _updateListsSync();
         await _saveAllConfigs();
         notifyListeners();
      }
  }

  void selectConfig(VpnConfigWithMetrics? c) {
     _selectedConfig = c;
     notifyListeners();
  }

  // --- HELPERS ---

  String _extractServerName(String raw) {
     try {
       final uri = Uri.parse(raw);
       if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
     } catch(e) {}
     
     // Fallback name
     final type = raw.split('://').first.toUpperCase();
     return '$type Server ${DateTime.now().millisecondsSinceEpoch % 1000}';
  }

  String? _extractCountryCode(String name) {
     final map = {
       '🇺🇸': 'US', '🇩🇪': 'DE', '🇬🇧': 'GB', '🇫🇷': 'FR', '🇯🇵': 'JP',
       '🇨🇦': 'CA', '🇦🇺': 'AU', '🇳🇱': 'NL', '🇸🇪': 'SE', '🇨🇭': 'CH',
       '🇸🇬': 'SG', '🇭🇰': 'HK', '🇰🇷': 'KR', '🇮🇳': 'IN', '🇧🇷': 'BR',
       '🇹🇷': 'TR', '🇮🇹': 'IT', '🇪🇸': 'ES', '🇵🇱': 'PL', '🇷🇺': 'RU', '🇮🇷': 'IR',
     };
     for (final e in map.entries) {
       if (name.contains(e.key)) return e.value;
     }
     return null;
  }
  
  // --- PERSISTENCE ---
  Future<void> _initDeviceId() async {
     final info = DeviceInfoPlugin();
     try {
       if (Platform.isAndroid) _currentDeviceId = 'android_${(await info.androidInfo).id}';
       else if (Platform.isWindows) _currentDeviceId = 'windows_${(await info.windowsInfo).deviceId}';
       else if (Platform.isIOS) _currentDeviceId = 'ios_${(await info.iosInfo).identifierForVendor}';
     } catch(e) { _currentDeviceId = 'unknown'; }
  }

  Future<void> _loadConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_configsKey);
      if (str != null) {
        final list = jsonDecode(str) as List;
        allConfigs = list.map((e) => VpnConfigWithMetrics.fromJson(e)).toList();
        AdvancedLogger.info('[ConfigManager] Loaded ${allConfigs.length} from storage');
      }
    } catch(e) {
       AdvancedLogger.error('[ConfigManager] Load error: $e');
       allConfigs = [];
    }
  }

  Future<void> _saveAllConfigs() async {
     try {
       final prefs = await SharedPreferences.getInstance();
       await prefs.setString(_configsKey, jsonEncode(allConfigs.map((e)=>e.toJson()).toList()));
     } catch(e) {
       AdvancedLogger.error('[ConfigManager] Save error: $e');
     }
  }

  void _updateListsSync() {
    // Main thread sorting (fast for <5000 items)
    validatedConfigs = allConfigs.where((c) => c.isValidated).toList();
    favoriteConfigs = allConfigs.where((c) => c.isFavorite).toList();

    int compare(VpnConfigWithMetrics a, VpnConfigWithMetrics b) => b.score.compareTo(a.score);

    allConfigs.sort(compare);
    validatedConfigs.sort(compare);
    favoriteConfigs.sort(compare);
  }

  Future<void> _loadAutoSwitchSetting() async {
     final p = await SharedPreferences.getInstance();
     _isAutoSwitchEnabled = p.getBool(_autoSwitchKey) ?? true;
  }
  Future<void> _saveAutoSwitchSetting() async {
     final p = await SharedPreferences.getInstance();
     await p.setBool(_autoSwitchKey, _isAutoSwitchEnabled);
  }

  // --- UI & LEGACY COMPATIBILITY METHODS ---
  Future<VpnConfigWithMetrics?> getBestConfig() async {
     if (_selectedConfig != null && _selectedConfig!.isValidated) return _selectedConfig;
     if (favoriteConfigs.isNotEmpty) return favoriteConfigs.first;
     if (validatedConfigs.isNotEmpty) return validatedConfigs.first;
     if (allConfigs.isNotEmpty) return allConfigs.first;
     return null;
  }

  void setConnected(bool c, {String status = 'Connected'}) {
     _isConnected = c;
     _connectionStatus = status;
     notifyListeners();
  }
  
  void stopSession() { _sessionTimer?.cancel(); }
  
  Future<void> clearAllData() async {
     final p = await SharedPreferences.getInstance();
     await p.remove(_configsKey);
     _selectedConfig = null;
     allConfigs.clear();
     _updateListsSync();
     notifyListeners();
  }
  
  // Aliases for compatibility
  Future<void> refreshAllConfigs() => fetchStartupConfigs();
  static Future<List<String>> parseAndFetchConfigs(String text) => parseMixedContent(text);
  Future<void> addConfig(String raw, String name) => addConfigs([raw]); 
  VpnConfigWithMetrics? getConfigById(String id) => allConfigs.firstWhereOrNull((c) => c.id == id);
  Future<void> disconnectVpn() async { setConnected(false, status: 'Disconnected'); }
  Future<VpnConfigWithMetrics?> runQuickTestOnAllConfigs(Function(String)? log) async { return getBestConfig(); }
  
  // Dummy implementations for Hot-Swap to prevent compilation errors (can be implemented later)
  Future<void> considerCandidate(VpnConfigWithMetrics c) async {} 
  void startHotSwap() {} 
  void stopHotSwap() {} 
}

// --- ISOLATE WORKER ---
// Deprecated: Sorting moved to main thread for better performance with frequent updates