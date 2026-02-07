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
import '../utils/clipboard_utils.dart';
import 'config_importer.dart';

class ConfigManager extends ChangeNotifier {
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();

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
  Duration _remainingTime = Duration.zero;
  VoidCallback? _onSessionExpiredCallback;

  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  bool _isAutoSwitchEnabled = true;
  bool get isAutoSwitchEnabled => _isAutoSwitchEnabled;
  set isAutoSwitchEnabled(bool value) {
    _isAutoSwitchEnabled = value;
    _saveAutoSwitchSetting();
    notifyListeners();
  }

  static const String _configsKey = 'vpn_configs';
  static const String _autoSwitchKey = 'auto_switch_enabled';

  // --- INITIALIZATION ---
  Future<void> init() async {
    AdvancedLogger.info('[ConfigManager] Initializing...');
    await _initDeviceId();
    await _loadAutoSwitchSetting();
    await _loadConfigs();

    if (allConfigs.isEmpty) {
       AdvancedLogger.info('[ConfigManager] No configs, fetching from remote...');
       await fetchStartupConfigs();
    }
    
    _updateLists();
    // Fire and forget startup refresh to get latest updates
    fetchStartupConfigs(); 
  }

  // --- DOWNLOAD LOGIC (FIXED: Direct GitHub, Smart Parser) ---
  Future<void> fetchStartupConfigs() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();

    try {
      AdvancedLogger.info('[ConfigManager] Downloading configs from GitHub...');
      
      String content = '';
      bool downloadSuccess = false;

      // 1. Direct GitHub URL (No Proxy)
      try {
        const directUrl = 'https://raw.githubusercontent.com/mobinsamadir/ivpn-servers/main/servers.txt';
        AdvancedLogger.info('[ConfigManager] Trying direct URL: $directUrl');
        
        final response = await http.get(Uri.parse(directUrl)).timeout(const Duration(seconds: 30));
        
        if (response.statusCode == 200) {
           if (_isHtmlResponse(response.body)) {
             AdvancedLogger.warn('[ConfigManager] Direct URL returned HTML (Proxy/Firewall issue)');
           } else {
             content = response.body;
             downloadSuccess = true;
             AdvancedLogger.info('📥 Downloaded ${content.length} bytes from Direct URL');
           }
        } else {
           AdvancedLogger.warn('[ConfigManager] Direct download HTTP error: ${response.statusCode}');
        }
      } catch (e) {
        AdvancedLogger.warn('[ConfigManager] Direct download failed: $e');
      }

      // 2. Fallback Mirror (JSDelivr)
      if (!downloadSuccess) {
        try {
          const fallbackUrl = 'https://fastly.jsdelivr.net/gh/mobinsamadir/ivpn-servers@main/servers.txt';
          AdvancedLogger.info('[ConfigManager] Trying fallback URL: $fallbackUrl');
          
          final response = await http.get(Uri.parse(fallbackUrl)).timeout(const Duration(seconds: 30));
          
          if (response.statusCode == 200) {
             if (_isHtmlResponse(response.body)) {
                AdvancedLogger.warn('[ConfigManager] Fallback URL returned HTML');
             } else {
                content = response.body;
                downloadSuccess = true;
                AdvancedLogger.info('📥 Downloaded ${content.length} bytes from Fallback URL');
             }
          }
        } catch (e) {
          AdvancedLogger.error('[ConfigManager] Fallback failed: $e');
        }
      }

      if (downloadSuccess) {
        // Use Smart Parser
        final configUrls = await parseMixedContent(content);
        
        if (configUrls.isNotEmpty) {
           int added = await addConfigs(configUrls);
           AdvancedLogger.info('[ConfigManager] Import finished: Added $added new configs from remote.');
        } else {
           AdvancedLogger.warn('[ConfigManager] Content downloaded but no valid configs found via Smart Parser.');
        }
      } else {
         AdvancedLogger.error('[ConfigManager] Failed to download configs from any source.');
      }
    } catch (e) {
       AdvancedLogger.error('[ConfigManager] Unexpected error in fetchStartupConfigs: $e');
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  // --- SMART PARSER (Regex Extraction & Recursion) ---
  static Future<List<String>> parseMixedContent(String text) async {
    final allConfigs = <String>{};
    
    String processedText = text;
    // Try Base64 Decode
    try {
      final decoded = utf8.decode(base64Decode(text.replaceAll(RegExp(r'\s+'), '')));
      if (decoded.contains('://')) processedText = decoded;
    } catch (e) {}

    // Extract Configs (Safe Regex with Triple Quotes)
    final regex = RegExp(
      r'''(vmess|vless|ss|trojan|tuic|hysteria|hysteria2):\/\/[a-zA-Z0-9-._~:/?#\[\]@!$&()*+,;=%]+(?:#[^#\n\r]*)?''',
      caseSensitive: false,
      multiLine: true,
    );
    
    for (final match in regex.allMatches(processedText)) {
       final config = match.group(0);
       if (config != null) allConfigs.add(config.trim());
    }

    // Extract Subs (Recursion)
    final linkRegex = RegExp(r'''https?:\/\/[^\s"\'<>\n\r`{}|\[\]]+''', caseSensitive: false);
    final linkMatches = linkRegex.allMatches(processedText);
    
    for (final match in linkMatches) {
       final link = match.group(0);
       // Only fetch if it's a valid sub link AND not already parsed as a config scheme
       if (link != null && _isValidSubscriptionLink(link)) {
          try {
             AdvancedLogger.info('[ConfigManager] Found sub link: $link');
             final res = await http.get(Uri.parse(link)).timeout(const Duration(seconds: 10));
             if (res.statusCode == 200 && !_isHtmlResponse(res.body)) {
                // Recursive call to parse content of the sub link
                final subConfigs = await parseMixedContent(res.body);
                allConfigs.addAll(subConfigs);
             }
          } catch(e) {
             AdvancedLogger.warn('[ConfigManager] Failed to fetch sub link: $link');
          }
       }
    }
    return allConfigs.toList();
  }

  // --- CORE METHODS ---
  Future<int> addConfigs(List<String> configStrings) async {
    int addedCount = 0;
    for (final raw in configStrings) {
      final trimmedRaw = raw.trim();
      if (allConfigs.any((c) => c.rawConfig.trim() == trimmedRaw)) continue;
      
      final name = _extractServerName(trimmedRaw);
      final id = 'config_${DateTime.now().millisecondsSinceEpoch}_$addedCount';
      
      allConfigs.add(VpnConfigWithMetrics(
        id: id,
        rawConfig: trimmedRaw,
        name: name,
        countryCode: _extractCountryCode(name),
      ));
      addedCount++;
    }
    
    if (addedCount > 0) {
      _updateLists();
      await _saveAllConfigs();
      notifyListeners();
    }
    return addedCount;
  }
  
  // Helpers
  static bool _isHtmlResponse(String body) {
    final t = body.trim().toLowerCase();
    return t.startsWith('<!doctype') || t.startsWith('<html') || t.contains('<body');
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
     final type = raw.split('://').first.toUpperCase();
     return '$type Server ${DateTime.now().millisecondsSinceEpoch % 1000}';
  }

  String? _extractCountryCode(String name) {
     final map = {
       '🇺🇸': 'US', '🇩🇪': 'DE', '🇬🇧': 'GB', '🇫🇷': 'FR', '🇯🇵': 'JP',
       '🇨🇦': 'CA', '🇦🇺': 'AU', '🇳🇱': 'NL', '🇸🇪': 'SE', '🇨🇭': 'CH',
       '🇸🇬': 'SG', '🇭🇰': 'HK', '🇰🇷': 'KR', '🇮🇳': 'IN', '🇧🇷': 'BR',
       '🇹🇷': 'TR', '🇮🇹': 'IT', '🇪🇸': 'ES', '🇵🇱': 'PL', '🇷🇺': 'RU',
     };
     for (final e in map.entries) {
       if (name.contains(e.key)) return e.value;
     }
     return null;
  }
  
  // Boilerplate methods
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

  void _updateLists() {
     validatedConfigs = allConfigs.where((c) => c.isValidated).toList();
     favoriteConfigs = allConfigs.where((c) => c.isFavorite).toList();
     // Sort desc by score
     allConfigs.sort((a, b) => b.score.compareTo(a.score));
     validatedConfigs.sort((a, b) => b.score.compareTo(a.score));
     favoriteConfigs.sort((a, b) => b.score.compareTo(a.score));
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

  Future<VpnConfigWithMetrics?> getBestConfig() async {
     if (_selectedConfig != null && _selectedConfig!.isValidated) return _selectedConfig;
     if (favoriteConfigs.isNotEmpty) return favoriteConfigs.first;
     if (validatedConfigs.isNotEmpty) return validatedConfigs.first;
     if (allConfigs.isNotEmpty) return allConfigs.first;
     return null;
  }

  Future<void> _loadAutoSwitchSetting() async {
     final p = await SharedPreferences.getInstance();
     _isAutoSwitchEnabled = p.getBool(_autoSwitchKey) ?? true;
  }
  Future<void> _saveAutoSwitchSetting() async {
     final p = await SharedPreferences.getInstance();
     await p.setBool(_autoSwitchKey, _isAutoSwitchEnabled);
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
  
  // Legacy aliases for UI compatibility
  Future<void> refreshAllConfigs() => fetchStartupConfigs();
  static Future<List<String>> parseAndFetchConfigs(String text) => parseMixedContent(text);
  Future<void> addConfig(String raw, String name) => addConfigs([raw]); 
  VpnConfigWithMetrics? getConfigById(String id) => allConfigs.firstWhereOrNull((c) => c.id == id);
  Future<void> disconnectVpn() async { setConnected(false, status: 'Disconnected'); }
  Future<VpnConfigWithMetrics?> runQuickTestOnAllConfigs(Function(String)? log) async { return getBestConfig(); }
  void printInventoryReport() {}
}