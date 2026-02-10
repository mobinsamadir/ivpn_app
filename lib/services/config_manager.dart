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
    _updateLists();
    AdvancedLogger.info('[ConfigManager] Initialization complete. Loaded ${allConfigs.length} configs.');
  }

  // --- CORE: FETCH & PARSE ---
  Future<void> fetchStartupConfigs() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();

    try {
      AdvancedLogger.info('[ConfigManager] Downloading configs from mirrors...');
      
      // لیست میرورها (لینک گیتهاب اولویت دارد)
      final mirrors = [
        'https://gist.githubusercontent.com/mobinsamadir/687a7ef199d6eaf6d1912e36151a9327/raw/servers.txt',
        'https://drive.google.com/uc?export=download&id=1S7CI5xq4bbnERZ1i1eGuYn5bhluh2LaW',
        'https://textshare.me/s/SbeuWi',
      ];

      String content = '';
      bool downloadSuccess = false;

      for (final url in mirrors) {
        if (downloadSuccess) break;
        try {
          AdvancedLogger.info('[ConfigManager] Attempting fetch from: $url');
          
          // FIX: Added User-Agent to bypass Google Drive HTML block
          final response = await http.get(
            Uri.parse(url),
            headers: {
              "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
              "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
              "Accept-Language": "en-US,en;q=0.5",
            },
          ).timeout(const Duration(seconds: 30));
          
          if (response.statusCode == 200) {
            if (_isHtmlResponse(response.body)) {
               AdvancedLogger.warn('[ConfigManager] Drive returned HTML (Blocked): $url');
            } else {
               content = response.body;
               downloadSuccess = true;
               AdvancedLogger.info('✅ Downloaded ${content.length} bytes successfully.');
            }
          } else {
             AdvancedLogger.warn('[ConfigManager] HTTP Error ${response.statusCode} from $url');
          }
        } catch (e) {
          AdvancedLogger.warn('[ConfigManager] Failed to fetch from $url: $e');
        }
      }

      if (downloadSuccess) {
        // 1. Parse Mixed Content (Configs + Sub Links)
        final configUrls = await parseMixedContent(content);
        
        if (configUrls.isNotEmpty) {
           // 2. SANITIZE: Remove malicious fields
           final cleanedConfigs = configUrls.map((c) {
             return c.replaceAll(RegExp(r'"spider_x":\s*("[^"]*"|[^,{}]+),?'), '');
           }).toList();
           
           // 3. Add to Database
           int added = await addConfigs(cleanedConfigs);
           AdvancedLogger.info('[ConfigManager] Import finished: Added $added new configs.');
        } else {
           AdvancedLogger.warn('[ConfigManager] No valid configs found in content.');
        }
      } else {
        AdvancedLogger.error('[ConfigManager] All attempts to fetch configs failed.');
      }
    } catch (e) {
       AdvancedLogger.error('[ConfigManager] Critical error in fetchStartupConfigs: $e');
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  // --- SMART PARSER (Regex Extraction & Recursion) ---
  static Future<List<String>> parseMixedContent(String text) async {
    final collectedConfigs = <String>{};
    
    String processedText = text;
    // Try Base64 Decode first
    try {
      final decoded = utf8.decode(base64Decode(text.replaceAll(RegExp(r'\s+'), '')));
      if (decoded.contains('://')) processedText = decoded;
    } catch (e) {}

    // Extract Standard Configs
    final regex = RegExp(
      r'''(vmess|vless|ss|trojan|tuic|hysteria|hysteria2):\/\/[a-zA-Z0-9-._~:/?#\[\]@!$&()*+,;=%]+(?:#[^#\n\r]*)?''',
      caseSensitive: false,
      multiLine: true,
    );
    
    for (final match in regex.allMatches(processedText)) {
       final config = match.group(0);
       if (config != null) collectedConfigs.add(config.trim());
    }

    // Extract Subscription Links (Recursion)
    final linkRegex = RegExp(r'''https?:\/\/[^\s"\'<>\n\r`{}|\[\]]+''', caseSensitive: false);
    final linkMatches = linkRegex.allMatches(processedText);
    
    for (final match in linkMatches) {
       final link = match.group(0);
       // Fetch only if it looks like a sub link and NOT a config protocol
       if (link != null && _isValidSubscriptionLink(link)) {
          try {
             // Avoid recursive loops with simple check (not robust but helpful)
             if (link.contains('google.com') || link.length < 15) continue;

             AdvancedLogger.info('[ConfigManager] Found sub link, fetching: $link');
             final res = await http.get(Uri.parse(link)).timeout(const Duration(seconds: 10));
             
             if (res.statusCode == 200 && !_isHtmlResponse(res.body)) {
                // Recursive call
                final subConfigs = await parseMixedContent(res.body);
                collectedConfigs.addAll(subConfigs);
             }
          } catch(e) {
             AdvancedLogger.warn('[ConfigManager] Failed to fetch sub link: $link');
          }
       }
    }
    return collectedConfigs.toList();
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
      _updateLists();
      await _saveAllConfigs();
      notifyListeners();
    }
    return addedCount;
  }

  Future<void> updateConfigMetrics(String id, {int? ping, double? speed, bool? connectionSuccess}) async {
     final index = allConfigs.indexWhere((c) => c.id == id);
     if (index != -1) {
        allConfigs[index] = allConfigs[index].updateMetrics(
           deviceId: _currentDeviceId,
           ping: ping, 
           speed: speed, 
           connectionSuccess: connectionSuccess ?? false
        );
        _updateLists();
        await _saveAllConfigs();
        notifyListeners();
     }
  }

  Future<void> updateConfigDirectly(VpnConfigWithMetrics config) async {
     final index = allConfigs.indexWhere((c) => c.id == config.id);
     if (index != -1) {
        allConfigs[index] = config;
     } else {
        // Option to add if missing, but usually we just update existing
     }
     _updateLists();
     await _saveAllConfigs();
     notifyListeners();
  }
  
  Future<void> markSuccess(String id) async {
      final index = allConfigs.indexWhere((c) => c.id == id);
      if (index != -1) {
         allConfigs[index] = allConfigs[index].copyWith(
            failureCount: 0,
            lastSuccessfulConnectionTime: DateTime.now().millisecondsSinceEpoch,
            isAlive: true
         );
         _updateLists();
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
         _updateLists();
         await _saveAllConfigs();
         notifyListeners();
      }
  }

  Future<bool> deleteConfig(String id) async {
     allConfigs.removeWhere((c) => c.id == id);
     if (_selectedConfig?.id == id) _selectedConfig = null;
     _updateLists();
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
         _updateLists();
         await _saveAllConfigs();
         notifyListeners();
      }
  }

  void selectConfig(VpnConfigWithMetrics? c) {
     _selectedConfig = c;
     notifyListeners();
  }

  // --- HELPERS ---
  static bool _isHtmlResponse(String body) {
    final t = body.trim().toLowerCase();
    return t.startsWith('<!doctype') || t.startsWith('<html') || t.contains('virus scan warning');
  }

  static bool _isValidSubscriptionLink(String link) {
    final l = link.toLowerCase();
    return !l.startsWith('vmess') && !l.startsWith('vless') && 
           !l.startsWith('ss') && !l.startsWith('trojan') &&
           !l.startsWith('hysteria') && !l.startsWith('tuic');
  }

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

  Future<void> _updateLists() async {
    try {
      final result = await compute(_isolateSortAndFilter, allConfigs);
      allConfigs = result['all']!;
      validatedConfigs = result['validated']!;
      favoriteConfigs = result['favorite']!;
    } catch (e) {
      AdvancedLogger.error('Sorting failed: $e');
      // Fallback to main thread sorting if isolate fails
      validatedConfigs = allConfigs.where((c) => c.isValidated).toList();
      favoriteConfigs = allConfigs.where((c) => c.isFavorite).toList();
      allConfigs.sort((a, b) => b.score.compareTo(a.score));
      validatedConfigs.sort((a, b) => b.score.compareTo(a.score));
      favoriteConfigs.sort((a, b) => b.score.compareTo(a.score));
    }
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
     allConfigs.clear(); _updateLists(); notifyListeners();
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
Map<String, List<VpnConfigWithMetrics>> _isolateSortAndFilter(List<VpnConfigWithMetrics> configs) {
  // Use a copy to sort, although Isolate automatically copies input data.
  // The 'configs' list is a copy of 'allConfigs' passed from main isolate.
  final all = List<VpnConfigWithMetrics>.from(configs);

  final validated = all.where((c) => c.isValidated).toList();
  final favorite = all.where((c) => c.isFavorite).toList();

  int compare(VpnConfigWithMetrics a, VpnConfigWithMetrics b) => b.score.compareTo(a.score);

  all.sort(compare);
  validated.sort(compare);
  favorite.sort(compare);

  return {
    'all': all,
    'validated': validated,
    'favorite': favorite,
  };
}