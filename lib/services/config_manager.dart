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

  // Watchdog variables
  Timer? _watchdogTimer;
  final Duration _watchdogInterval = const Duration(seconds: 45);
  int _consecutiveFailures = 0;

  // Hot-Swap Logic
  VpnConfigWithMetrics? _currentBestCandidate;
  Future<void> Function(VpnConfigWithMetrics)? onHotSwap;
  bool _isHotSwapActive = false;

  void startHotSwap() {
    _isHotSwapActive = true;
    _currentBestCandidate = null;
    notifyListeners();
  }

  void stopHotSwap() {
    _isHotSwapActive = false;
    notifyListeners();
  }

  Future<void> considerCandidate(VpnConfigWithMetrics candidate) async {
     if (!_isHotSwapActive) return;

     // Only consider valid candidates with good ping
     if (candidate.currentPing <= 0 || candidate.currentPing > 3000) return;

     bool isBetter = false;

     if (_currentBestCandidate == null) {
       isBetter = true;
     } else {
       // Compare scores: Lower priorityScore is better
       // Priority Score: (Latency * 0.7) + (Jitter * 0.3)
       // We use a margin to prevent flipping (e.g., must be 20% better)
       final currentScore = _currentBestCandidate!.priorityScore;
       final newScore = candidate.priorityScore;

       if (newScore < currentScore * 0.8) { // 20% improvement
         isBetter = true;
       }
     }

     if (isBetter) {
        AdvancedLogger.info('[ConfigManager] New Hot-Swap Candidate: ${candidate.name} (Score: ${candidate.priorityScore.toStringAsFixed(1)})');
        _currentBestCandidate = candidate;

        // Notify UI to swap
        if (onHotSwap != null) {
           await onHotSwap!(candidate);
        }
     }
  }

  static const String _configsKey = 'vpn_configs';
  static const String _autoSwitchKey = 'auto_switch_enabled';

  // --- INITIALIZATION ---
  Future<void> init({bool fetchRemote = true}) async {
    AdvancedLogger.info('[ConfigManager] Initializing...');
    await _initDeviceId();
    await _loadAutoSwitchSetting();
    await _loadConfigs();

    if (allConfigs.isEmpty && fetchRemote) {
       AdvancedLogger.info('[ConfigManager] No configs, fetching from remote...');
       await fetchStartupConfigs();
    }
    
    _updateLists();
    // Fire and forget startup refresh to get latest updates
    if (fetchRemote) fetchStartupConfigs();
  }

  Future<void> fetchStartupConfigs() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();

    try {
      AdvancedLogger.info('[ConfigManager] Downloading configs from Google Drive...');

      const String driveUrl = 'https://drive.google.com/uc?export=download&id=1S7CI5xq4bbnERZ1i1eGuYn5bhluh2LaW';
      
      String content = '';
      bool downloadSuccess = false;
      int attempts = 0;
      const int maxAttempts = 3;

      while (attempts < maxAttempts && !downloadSuccess) {
        attempts++;
        try {
          AdvancedLogger.info('[ConfigManager] Attempt $attempts of $maxAttempts to fetch from Drive...');

          final response = await http.get(
            Uri.parse(driveUrl),
            headers: {
              "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
              "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            },
          ).timeout(const Duration(seconds: 60));
          
          if (response.statusCode == 200) {
            if (_isHtmlResponse(response.body)) {
               AdvancedLogger.warn('[ConfigManager] Drive returned HTML (Blocked): $driveUrl');
               // Drive might return HTML for rate limits or errors, treat as failure to retry
            } else {
               content = response.body;
               downloadSuccess = true;
               AdvancedLogger.info('✅ Downloaded ${content.length} bytes from Drive');
            }
          } else {
            AdvancedLogger.warn('[ConfigManager] Drive returned status code: ${response.statusCode}');
          }
        } catch (e) {
          AdvancedLogger.warn('[ConfigManager] Failed to fetch from Drive (Attempt $attempts): $e');
        }

        if (!downloadSuccess && attempts < maxAttempts) {
           final backoff = Duration(seconds: 2 * attempts); // 2s, 4s, 6s...
           AdvancedLogger.info('[ConfigManager] Retrying in ${backoff.inSeconds}s...');
           await Future.delayed(backoff);
        }
      }

      if (downloadSuccess) {
        // 1. Smart Parse
        final configUrls = await parseMixedContent(content);
        
        if (configUrls.isNotEmpty) {
           // 2. SANITIZE: Remove "spider_x" to prevent core crash
           final cleanedConfigs = configUrls.map((c) {
             // Remove "spider_x" field completely from JSON-like structures
             // Handles cases like "spider_x": "value", or "spider_x": 123,
             return c.replaceAll(RegExp(r'"spider_x":\s*("[^"]*"|[^,{}]+),?'), '')
                     // Also handle potential trailing comma issues if it was the last item
                     .replaceAll(RegExp(r',\s*}'), '}')
                     .trim();
           }).toList();
           
           // 3. Add to list
           int added = await addConfigs(cleanedConfigs);
           AdvancedLogger.info('[ConfigManager] Import finished: Added $added new configs.');
        } else {
           AdvancedLogger.warn('[ConfigManager] No valid configs found in downloaded content.');
        }
      } else {
        AdvancedLogger.error('[ConfigManager] All attempts to fetch from Drive failed.');
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
    
    // Create a set of existing configs for faster lookup
    final existingConfigs = allConfigs.map((c) => c.rawConfig.trim()).toSet();
    
    for (final raw in configStrings) {
      final trimmedRaw = raw.trim();
      if (existingConfigs.contains(trimmedRaw)) continue;

      final name = _extractServerName(trimmedRaw);
      final id = 'config_${DateTime.now().millisecondsSinceEpoch}_$addedCount';

      allConfigs.add(VpnConfigWithMetrics(
        id: id,
        rawConfig: trimmedRaw,
        name: name,
        countryCode: _extractCountryCode(name),
      ));
      existingConfigs.add(trimmedRaw); // Add to set to prevent duplicates in same batch
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

  Future<void> updateConfigMetrics(String id, {int? ping, double? speed, double? jitter, bool? connectionSuccess}) async {
     final index = allConfigs.indexWhere((c) => c.id == id);
     if (index != -1) {
        allConfigs[index] = allConfigs[index].updateMetrics(
           deviceId: _currentDeviceId,
           ping: ping, 
           speed: speed, 
           jitter: jitter,
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

     if (_isConnected) {
       _startWatchdog();
     } else {
       _stopWatchdog();
     }
  }

  void stopSession() { _sessionTimer?.cancel(); }
  Future<void> clearAllData() async {
     final p = await SharedPreferences.getInstance();
     await p.remove(_configsKey);
     allConfigs.clear(); _updateLists(); notifyListeners();
  }
  
  // Watchdog Implementation
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _consecutiveFailures = 0;
    _watchdogTimer = Timer.periodic(_watchdogInterval, (timer) {
      if (_isConnected) {
        _performHealthCheck();
      } else {
        _stopWatchdog();
      }
    });
    AdvancedLogger.info('[Watchdog] Started monitoring connection...');
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    AdvancedLogger.info('[Watchdog] Stopped monitoring.');
  }

  Future<void> _performHealthCheck() async {
    if (!_isConnected || _selectedConfig == null) return;

    int failures = 0;
    int totalLatency = 0;
    int successfulPings = 0;

    // Perform 3 checks
    for (int i = 0; i < 3; i++) {
       try {
         final sw = Stopwatch()..start();
         final client = HttpClient();
         client.connectionTimeout = const Duration(milliseconds: 3000);
         // Use a common target that responds to HEAD
         final req = await client.headUrl(Uri.parse('http://cp.cloudflare.com'))
             .timeout(const Duration(milliseconds: 3000));
         final res = await req.close()
             .timeout(const Duration(milliseconds: 3000));
         sw.stop();

         if (res.statusCode == 200 || res.statusCode == 204) {
            final latency = sw.elapsedMilliseconds;
            totalLatency += latency;
            successfulPings++;
            // If latency is very high, we count it towards the high latency check later
         } else {
            failures++;
         }
       } catch (e) {
         failures++;
       }
       await Future.delayed(const Duration(milliseconds: 200));
    }

    bool shouldFail = false;

    // 1. Packet Loss > 50% (2 or more failures out of 3)
    if (failures >= 2) shouldFail = true;

    // 2. Avg Ping > 3000ms
    if (successfulPings > 0) {
       final avgPing = totalLatency / successfulPings;
       if (avgPing > 3000) shouldFail = true;
    }

    if (shouldFail) {
       _consecutiveFailures++;
       AdvancedLogger.warn('[Watchdog] Health check failed. Loss: $failures/3');

       // React immediately
       final failedId = _selectedConfig!.id;
       await markFailure(failedId);

       final nextBest = await getBestConfig();
       if (nextBest != null && nextBest.id != failedId) {
          AdvancedLogger.info('[Watchdog] Switching to next best: ${nextBest.name}');
          if (onHotSwap != null) {
             onHotSwap!(nextBest);
          }
       }
    } else {
       _consecutiveFailures = 0;
       if (successfulPings > 0) {
          // Update metrics with fresh data
          updateConfigMetrics(
             _selectedConfig!.id,
             ping: (totalLatency / successfulPings).toInt(),
             connectionSuccess: true
          );
       }
    }
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