import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';
import 'package:html/parser.dart' as html_parser;
import '../models/vpn_config_with_metrics.dart';
import '../utils/advanced_logger.dart';
import '../utils/cancellable_operation.dart';

class ConfigManager extends ChangeNotifier {
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();

  // --- STATE VARIABLES ---
  List<VpnConfigWithMetrics> allConfigs = [];
  List<VpnConfigWithMetrics> validatedConfigs = [];
  List<VpnConfigWithMetrics> favoriteConfigs = [];
  List<VpnConfigWithMetrics> reserveList = []; // Fallback servers

  CancelToken? _scanCancelToken;

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
  Timer? _heartbeatTimer; // Smart Monitor
  bool _hasPendingUpdates = false; // Flag for buffered updates

  // Global Kill Switch
  bool _isGlobalStopRequested = false;
  bool get isGlobalStopRequested => _isGlobalStopRequested;

  // Callbacks
  Future<void> Function()? onTriggerFunnel;
  Function(VpnConfigWithMetrics)? onAutoSwitch;
  Future<void> Function()? stopVpnCallback;

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

  CancelToken getScanCancelToken() {
    _scanCancelToken?.cancel();
    _scanCancelToken = CancelToken();
    return _scanCancelToken!;
  }

  void cancelScan() {
    if (_scanCancelToken != null && !_scanCancelToken!.isCancelled) {
      _scanCancelToken!.cancel();
      AdvancedLogger.info('[ConfigManager] Scan cancelled via token.');
    }
  }

  Future<void> stopAllOperations() async {
    AdvancedLogger.info('[ConfigManager] 🛑 STOP ALL OPERATIONS REQUESTED');
    _isGlobalStopRequested = true;
    cancelScan();
    stopSmartMonitor();
    if (stopVpnCallback != null) {
      await stopVpnCallback!();
    }
    notifyListeners();
  }

  // --- CORE: FETCH & PARSE ---
  Future<bool> fetchStartupConfigs() async {
    if (_isRefreshing) return false;
    _isRefreshing = true;
    _isGlobalStopRequested = false; // Reset flag on new operation
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

      for (var url in mirrors) {
        if (anyConfigAdded) break; // Chain Breaking: Stop if we already have configs

        // Auto-convert Google Drive /view links to direct download
        if (url.contains('drive.google.com') && url.contains('/view')) {
           final fileIdMatch = RegExp(r'\/d\/([a-zA-Z0-9_-]+)').firstMatch(url);
           if (fileIdMatch != null) {
              final fileId = fileIdMatch.group(1);
              url = 'https://drive.google.com/uc?export=download&id=$fileId';
              AdvancedLogger.info('[ConfigManager] Converted Drive View Link to: $url');
           }
        }

        try {
          AdvancedLogger.info('[ConfigManager] Attempting fetch from: $url');
          
          final response = await http.get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9',
              'Sec-Fetch-Dest': 'document',
              'Sec-Fetch-Mode': 'navigate',
            },
          ).timeout(const Duration(seconds: 30)); // Increased timeout to 30s
          
          if (response.statusCode == 200) {
            String content = response.body;

            // Check for Google Drive "Virus scan warning" or confirmation
            // Logic: Response body > 100KB AND contains html tag OR confirm=
            if (url.contains('drive.google.com') &&
                ((content.length > 100000 && content.contains('<html')) ||
                 content.contains('Google Drive - Virus scan warning') ||
                 content.contains('confirm='))) {

               AdvancedLogger.info('[ConfigManager] Detected Drive Warning/Large File. Parsing confirmation link...');

               // 1. Extract token using simple Regex first (Fast)
               final confirmMatch = RegExp(r'confirm=([a-zA-Z0-9_-]+)').firstMatch(content);
               String? confirmToken = confirmMatch?.group(1);

               String? nextUrl;
               if (confirmToken != null) {
                   // Construct URL directly if token found
                   final fileIdMatch = RegExp(r'id=([a-zA-Z0-9_-]+)').firstMatch(url);
                   final fileId = fileIdMatch?.group(1);
                   if (fileId != null) {
                      nextUrl = 'https://drive.google.com/uc?export=download&id=$fileId&confirm=$confirmToken';
                   }
               }

               // Fallback to HTML parsing if regex failed
               if (nextUrl == null) {
                   final confirmLink = extractDriveConfirmationLink(content);
                   if (confirmLink != null) {
                      nextUrl = confirmLink;
                      if (nextUrl.startsWith('/')) {
                         nextUrl = 'https://drive.google.com$nextUrl';
                      }
                   }
               }

               if (nextUrl != null) {
                  AdvancedLogger.info('[ConfigManager] Fetching confirmation URL: $nextUrl');
                  try {
                    final nextResponse = await http.get(Uri.parse(nextUrl), headers: {
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
                        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
                        'Accept-Language': 'en-US,en;q=0.9',
                        'Sec-Fetch-Dest': 'document',
                        'Sec-Fetch-Mode': 'navigate',
                    }).timeout(const Duration(seconds: 30));

                    if (nextResponse.statusCode == 200) {
                       content = nextResponse.body;
                       AdvancedLogger.info('✅ Downloaded confirmed content: ${content.length} bytes.');
                    }
                  } catch (e) {
                    AdvancedLogger.warn('[ConfigManager] Failed to fetch confirmed link: $e');
                  }
               }
            }

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

  // --- SMART PARSER (Enhanced: ID -> Anchor -> Form -> Debug) ---
  static String? extractDriveConfirmationLink(String html) {
     try {
       var document = html_parser.parse(html);

       // 1. Strict ID Check
       var element = document.getElementById('uc-download-link');
       var href = element?.attributes['href'];
       if (href != null) return _normalizeUrl(href);

       // 2. Fallback: Any Anchor with confirm=
       AdvancedLogger.info('[ConfigManager] #uc-download-link not found. Trying fallback <a> search...');
       var anchor = document.querySelector('a[href*="confirm="]');
       href = anchor?.attributes['href'];
       if (href != null) return _normalizeUrl(href);

       // 3. Fallback: Form Action
       AdvancedLogger.info('[ConfigManager] Anchor not found. Trying fallback <form> search...');
       var form = document.querySelector('form[action*="confirm="]');
       var action = form?.attributes['action'];
       if (action != null) return _normalizeUrl(action);

       // 4. Debug Log (CRITICAL)
       AdvancedLogger.warn('[ConfigManager] ❌ Failed to extract confirmation link. Dumping HTML start:');
       AdvancedLogger.warn(html.substring(0, math.min(1000, html.length)));

     } catch (e) {
       AdvancedLogger.warn('[ConfigManager] Error extracting confirmation link: $e');
     }
     return null;
  }

  static String _normalizeUrl(String url) {
      var normalized = url.replaceAll('&amp;', '&');
      if (normalized.startsWith('/')) {
         return 'https://drive.google.com$normalized';
      }
      return normalized;
  }

  static String _fixBase64Padding(String s) {
    while (s.length % 4 != 0) {
      s += '=';
    }
    return s;
  }

  static Future<List<String>> parseMixedContent(String text) async {
    final collectedConfigs = <String>{};
    
    String processedText = text;

    // 1. Detect & Parse HTML (The Bulletproof Fix)
    // If it looks like HTML, use the parser to get clean text (decodes entities automatically)
    if (text.trimLeft().startsWith('<') || text.contains('<!DOCTYPE html>')) {
       try {
         var document = html_parser.parse(text);
         // .text automatically decodes &amp; -> & and strips tags
         final bodyText = document.body?.text ?? '';

         // Also extract hrefs from anchor tags to catch links
         final hrefs = document.querySelectorAll('a')
             .map((e) => e.attributes['href'])
             .whereType<String>()
             .join('\n');

         processedText = '$bodyText\n$hrefs';
       } catch (e) {
         AdvancedLogger.warn('[ConfigManager] HTML parsing failed, falling back to raw text: $e');
       }
    } else {
       // 2. Base64 Decode Attempt (Only if not HTML)
       try {
         String cleanText = text.replaceAll(RegExp(r'\s+'), '');
         cleanText = _fixBase64Padding(cleanText);
         final decoded = utf8.decode(base64Decode(cleanText));
         if (decoded.contains('://')) processedText = decoded;
       } catch (e) {
         // Not base64
       }
    }

    // 3. Extract Configs using RELAXED "Terminator" Regex
    // Capture everything until whitespace, <, ", ', or ` (backtick)
    final regex = RegExp(
      r'''(vless|vmess|trojan|ss):\/\/[^\s<"'`]+''',
      caseSensitive: false,
      multiLine: true,
    );
    
    for (final match in regex.allMatches(processedText)) {
       var rawConfig = match.group(0)?.trim();
       if (rawConfig != null && rawConfig.isNotEmpty) {
          var config = rawConfig;
          try {
             // Basic Sanitization (Remove trailing punctuation if regex overshot)
             const junkChars = {'.', ',', ')', '?', ';', '&'};
             while (config.isNotEmpty && junkChars.contains(config[config.length - 1])) {
               config = config.substring(0, config.length - 1);
             }

             // Fix Base64 Padding for vmess/trojan
             if (config.startsWith('vmess://')) {
                 final base64Part = config.substring(8);
                 // vmess body is usually base64 encoded JSON, no @
                 if (!base64Part.contains('@')) {
                     var fixedBase64 = base64Part;
                     while (fixedBase64.length % 4 != 0) {
                         fixedBase64 += '=';
                     }
                     if (fixedBase64 != base64Part) {
                         config = 'vmess://$fixedBase64';
                     }
                 }
             } else if (config.startsWith('trojan://')) {
                 // Some trojan links are base64 encoded (rare but exists)
                 // Standard: trojan://password@...
                 // If no @, assume base64
                 final base64Part = config.substring(9);
                 if (!base64Part.contains('@')) {
                      var fixedBase64 = base64Part;
                      while (fixedBase64.length % 4 != 0) {
                          fixedBase64 += '=';
                      }
                      if (fixedBase64 != base64Part) {
                          config = 'trojan://$fixedBase64';
                      }
                 }
             }

             if (config.contains('%')) {
                config = Uri.decodeFull(config);
             }
             collectedConfigs.add(config);
          } catch (e) {
             AdvancedLogger.error("Failed to parse extracted config. Raw String: >>>$config<<<", error: e);
          }
       }
    }
    
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

  // --- ACTIVE CONNECTION PING & NAVIGATION ---

  Future<int> measureActivePing() async {
    if (!_isConnected || _selectedConfig == null) return -1;

    final stopwatch = Stopwatch()..start();
    try {
      final response = await http.head(
        Uri.parse('https://www.google.com'),
      ).timeout(const Duration(seconds: 3));

      stopwatch.stop();
      if (response.statusCode == 200) {
         final ping = stopwatch.elapsedMilliseconds;
         // Update metrics directly
         await updateConfigMetrics(_selectedConfig!.id, ping: ping, connectionSuccess: true);
         AdvancedLogger.info('[ConfigManager] Active ping success: ${ping}ms');
         return ping;
      }
    } catch (e) {
      AdvancedLogger.warn('[ConfigManager] Active ping failed: $e');
    }
    return -1;
  }

  VpnConfigWithMetrics? getNextConfig(List<VpnConfigWithMetrics> currentList) {
     if (currentList.isEmpty) return null;
     if (_selectedConfig == null) return currentList.first;

     final currentIndex = currentList.indexWhere((c) => c.id == _selectedConfig!.id);
     if (currentIndex == -1) return currentList.first;

     return currentList[(currentIndex + 1) % currentList.length];
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
     if (c) {
       startSmartMonitor();
     } else {
       stopSmartMonitor();
     }
     notifyListeners();
  }
  
  void stopSession() { _sessionTimer?.cancel(); }

  // --- SMART MONITOR (HEARTBEAT) ---
  void startSmartMonitor() {
    _heartbeatTimer?.cancel();
    if (!isAutoSwitchEnabled) return;

    AdvancedLogger.info('[ConfigManager] Starting Smart Monitor...');
    int failureCount = 0;

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
       if (!_isConnected) {
         timer.cancel();
         return;
       }

       final ping = await measureActivePing();

       // Logic: Fail if ping is -1 (error) or extremely high (>2000ms)
       if (ping == -1 || ping > 2000) {
          failureCount++;
          AdvancedLogger.warn('[Smart Monitor] Heartbeat failed. Count: $failureCount');

          if (failureCount >= 3) {
             AdvancedLogger.warn('[Smart Monitor] Threshold reached. Initiating Auto-Switch...');
             failureCount = 0;
             await _performAutoSwitch();
          }
       } else {
          failureCount = 0; // Reset on success
       }
    });
  }

  void stopSmartMonitor() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  Future<void> _performAutoSwitch() async {
    // 1. Check Reserve List
    if (reserveList.isNotEmpty) {
       final nextBest = reserveList.removeAt(0);
       AdvancedLogger.info('[Smart Monitor] Switching to reserve config: ${nextBest.name}');
       _selectedConfig = nextBest;
       notifyListeners();

       onAutoSwitch?.call(nextBest);
    } else {
       // 2. No reserves -> Trigger Funnel
       AdvancedLogger.info('[Smart Monitor] Reserve list empty. Triggering Funnel...');
       onTriggerFunnel?.call();
    }
  }

  Future<void> disconnectVpn() async {
    cancelScan();
    stopSmartMonitor();
    setConnected(false, status: 'Disconnected');
  }

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
  Future<VpnConfigWithMetrics?> runQuickTestOnAllConfigs(Function(String)? log) async { return getBestConfig(); }
  
  // Dummy implementations for Hot-Swap to prevent compilation errors (can be implemented later)
  Future<void> considerCandidate(VpnConfigWithMetrics c) async {} 
  void startHotSwap() {} 
  void stopHotSwap() {} 
}

// --- ISOLATE WORKER ---
// Deprecated: Sorting moved to main thread for better performance with frequent updates