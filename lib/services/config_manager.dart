import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart'; // Import crypto for MD5
import '../models/vpn_config_with_metrics.dart';
import '../utils/advanced_logger.dart';
import '../utils/cancellable_operation.dart';
import 'native_vpn_service.dart';
import 'testers/ephemeral_tester.dart';

// --- TOP-LEVEL HELPER FUNCTIONS FOR ISOLATE ---

String _extractServerName(String raw) {
  try {
    final uri = Uri.parse(raw);
    if (uri.fragment.isNotEmpty) {
      return Uri.decodeComponent(uri.fragment);
    }
  } catch(_) {}

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
    if (name.contains(e.key)) {
      return e.value;
    }
  }
  return null;
}

/// Isolate entry point for processing configs
Future<Map<String, dynamic>> _processConfigsInIsolate(Map<String, dynamic> args) async {
  final List<String> configStrings = args['configStrings'] as List<String>;
  final Set<String> blockedHashes = (args['blockedHashes'] as List).cast<String>().toSet();
  final bool checkBlacklist = args['checkBlacklist'] as bool;
  final Set<String> existingConfigs = (args['existingConfigs'] as List).cast<String>().toSet();
  int addedCount = args['initialAddedCount'] as int;

  final List<VpnConfigWithMetrics> newConfigs = [];
  final List<String> hashesToRemoveFromBlacklist = [];

  // Local set to avoid duplicates within the new batch
  final Set<String> batchConfigs = {};

  for (final raw in configStrings) {
    final trimmedRaw = raw.trim();
    if (trimmedRaw.isEmpty) continue;

    // HASH Check for Blacklist
    final hash = md5.convert(utf8.encode(trimmedRaw)).toString();

    if (checkBlacklist && blockedHashes.contains(hash)) {
       // Silently skip blacklisted config
       continue;
    }

    // Manual Overwrite: If adding with checkBlacklist=false, we mark hash for removal
    if (!checkBlacklist && blockedHashes.contains(hash)) {
       hashesToRemoveFromBlacklist.add(hash);
    }

    if (existingConfigs.contains(trimmedRaw)) {
      continue;
    }
    if (batchConfigs.contains(trimmedRaw)) {
      continue;
    }

    final name = _extractServerName(trimmedRaw);
    final id = 'config_${DateTime.now().millisecondsSinceEpoch}_$addedCount';

    newConfigs.add(VpnConfigWithMetrics(
      id: id,
      rawConfig: trimmedRaw,
      name: name,
      countryCode: _extractCountryCode(name),
      addedDate: DateTime.now(), // Ensure addedDate is set
    ));

    batchConfigs.add(trimmedRaw);
    addedCount++;
  }

  return {
    'newConfigs': newConfigs,
    'hashesToRemoveFromBlacklist': hashesToRemoveFromBlacklist,
    'addedCount': addedCount,
  };
}

/// Isolate entry point for sorting configs
Map<String, List<VpnConfigWithMetrics>> _sortConfigsInIsolate(List<VpnConfigWithMetrics> configs) {
  // Sort logic helper: Score Descending, then Date Descending
  int compareScore(VpnConfigWithMetrics a, VpnConfigWithMetrics b) {
     final scoreCmp = b.score.compareTo(a.score);
     if (scoreCmp != 0) return scoreCmp;
     return b.addedDate.compareTo(a.addedDate);
  }

  // Create local copy to sort
  final allConfigs = List<VpnConfigWithMetrics>.from(configs);
  allConfigs.sort(compareScore);

  final validatedConfigs = allConfigs.where((c) => c.isValidated).toList();
  final favoriteConfigs = allConfigs.where((c) => c.isFavorite).toList();

  // Ensure sublists are also sorted
  validatedConfigs.sort(compareScore);
  favoriteConfigs.sort(compareScore);

  return {
    'all': allConfigs,
    'validated': validatedConfigs,
    'favorite': favoriteConfigs,
  };
}

class ConfigManager extends ChangeNotifier {
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();

  // --- STATE VARIABLES ---
  List<VpnConfigWithMetrics> allConfigs = [];
  List<VpnConfigWithMetrics> validatedConfigs = [];
  List<VpnConfigWithMetrics> favoriteConfigs = [];
  List<VpnConfigWithMetrics> reserveList = []; // Fallback servers
  Set<String> _blockedConfigs = {}; // Blacklist for deleted configs

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
  static const String _blacklistKey = 'config_blacklist';
  static const String _autoSwitchKey = 'auto_switch_enabled';

  // --- INITIALIZATION ---
  Future<void> init() async {
    AdvancedLogger.info('[ConfigManager] Initializing...');
    await _initDeviceId();
    await _loadAutoSwitchSetting();
    await _loadBlacklist(); // Load Blacklist
    await _loadConfigs();
    await _updateLists();
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
  // Fetching logic migrated to ConfigGistService

  // --- THROTTLING LOGIC ---
  void notifyListenersThrottled() {
    if (_throttleTimer?.isActive ?? false) {
      _hasPendingUpdates = true;
      return;
    }

    _throttleTimer = Timer(const Duration(milliseconds: 500), _onThrottleTick);
  }

  Future<void> _onThrottleTick() async {
    await _updateLists(); // Async update via isolate
    _safeNotifyListeners();

    _throttleTimer = null;

    // If updates accumulated while waiting, trigger another cycle immediately
    if (_hasPendingUpdates) {
      _hasPendingUpdates = false;
      notifyListenersThrottled();
    }
  }

  // --- DATABASE OPERATIONS ---
  Future<int> addConfigs(List<String> configStrings, {bool checkBlacklist = true}) async {
    // Prepare data for Isolate
    // We pass list versions of Sets because Sets aren't always transferrable if they contain custom objects,
    // but Strings are fine. Just to be safe and consistent with typical isolate args.
    final args = {
      'configStrings': configStrings,
      'blockedHashes': _blockedConfigs.toList(),
      'checkBlacklist': checkBlacklist,
      'existingConfigs': allConfigs.map((c) => c.rawConfig.trim()).toList(),
      'initialAddedCount': 0, // We can let the isolate handle local count, or pass a global counter if needed.
                              // Current logic uses local addedCount in loop, let's stick to that but we risk ID collisions if we added multiple batches very fast.
                              // Actually the ID uses DateTime.now() inside the loop. In isolate, DateTime.now() is fine.
    };

    AdvancedLogger.info('[ConfigManager] Spawning isolate to process ${configStrings.length} configs...');

    try {
      final result = await compute(_processConfigsInIsolate, args);

      final newConfigs = result['newConfigs'] as List<VpnConfigWithMetrics>;
      final hashesToRemove = result['hashesToRemoveFromBlacklist'] as List<String>;

      // Update Blacklist
      if (hashesToRemove.isNotEmpty) {
         _blockedConfigs.removeAll(hashesToRemove);
         await _saveBlacklist();
         AdvancedLogger.info("[ConfigManager] Manual overwrite: Removed ${hashesToRemove.length} configs from blacklist.");
      }

      // Add New Configs
      if (newConfigs.isNotEmpty) {
         allConfigs.addAll(newConfigs);
         await _updateLists();
         await _saveAllConfigs();
         _safeNotifyListeners();
         AdvancedLogger.info('[ConfigManager] Successfully added ${newConfigs.length} configs via Isolate.');
      }

      return newConfigs.length;

    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Error in addConfigs isolate: $e');
      return 0;
    }
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
         await _updateLists();
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
         await _updateLists();
         await _saveAllConfigs();
         notifyListeners();
      }
  }

  // --- NEW: Mark Invalid ---
  Future<void> markInvalid(String id) async {
      final index = allConfigs.indexWhere((c) => c.id == id);
      if (index != -1) {
         AdvancedLogger.warn("[ConfigManager] Marking config invalid (Parsing/Init Error): ${allConfigs[index].name}");
         allConfigs[index] = allConfigs[index].copyWith(
            failureCount: 99, // High penalty
            isAlive: false,
            lastFailedStage: "Invalid_Config"
         );
         await _updateLists();
         await _saveAllConfigs();
         notifyListeners();
      }
  }

  Future<bool> deleteConfig(String id) async {
     final configIndex = allConfigs.indexWhere((c) => c.id == id);
     if (configIndex != -1) {
        final config = allConfigs[configIndex];

        // BLACKLIST LOGIC: Add hash to persistent blacklist
        final hash = md5.convert(utf8.encode(config.rawConfig.trim())).toString();
        _blockedConfigs.add(hash);
        await _saveBlacklist();
        AdvancedLogger.info("[ConfigManager] Config deleted and blacklisted: ${config.name} ($hash)");

        allConfigs.removeAt(configIndex);
        if (_selectedConfig?.id == id) _selectedConfig = null;
        await _updateLists();
        await _saveAllConfigs();
        notifyListeners();
        return true;
     }
     return false;
  }

  // --- CLEANUP METHODS ---
  Future<int> removeConfigs({bool failedTcp = false, bool dead = false}) async {
    final initialCount = allConfigs.length;
    allConfigs.removeWhere((c) {
      if (failedTcp && c.funnelStage == 0 && c.failureCount > 0) return true;
      if (dead && c.currentPing == -1) return true;
      return false;
    });

    if (allConfigs.length < initialCount) {
        if (_selectedConfig != null && !allConfigs.contains(_selectedConfig)) {
            _selectedConfig = null;
        }
        await _updateLists();
        await _saveAllConfigs();
        notifyListeners();
    }
    return initialCount - allConfigs.length;
  }

  Future<void> toggleFavorite(String id) async {
      final index = allConfigs.indexWhere((c) => c.id == id);
      if (index != -1) {
         allConfigs[index] = allConfigs[index].copyWith(
            isFavorite: !allConfigs[index].isFavorite
         );
         await _updateLists();
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
      ).timeout(const Duration(seconds: 5));

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

  Future<bool> skipToNext({List<VpnConfigWithMetrics>? sourceList, bool performConnection = true}) async {
    final list = sourceList ?? (validatedConfigs.isNotEmpty ? validatedConfigs : allConfigs);
    if (list.isEmpty) return false;

    int currentIndex = -1;
    if (_selectedConfig != null) {
      currentIndex = list.indexWhere((c) => c.id == _selectedConfig!.id);
    }

    // Find next valid config
    int attempts = 0;
    int nextIndex = currentIndex;
    VpnConfigWithMetrics? candidate;

    // Loop to find next valid one
    while (attempts < list.length) {
      nextIndex = (nextIndex + 1) % list.length;
      final c = list[nextIndex];
      // Smart Skip: Ignore obviously dead configs (failed 3+ times, no ping)
      // Also prevent wrapping to self if self is the only one (or all others dead)
      if (!c.isDead && (c.currentPing > 0 || c.funnelStage > 0)) {
        candidate = c;
        break;
      }
      attempts++;
    }

    // Fallback: If no "good" candidate found, we DO NOT blindly pick a dead one.
    // Instead, we return false to let UI inform user.
    if (candidate == null) {
       AdvancedLogger.warn("[ConfigManager] Smart Skip: No valid candidates found.");
       return false;
    }

    // If candidate is same as current, it means only 1 valid config exists.
    if (candidate.id == _selectedConfig?.id) {
       AdvancedLogger.info("[ConfigManager] Smart Skip: Already on the only valid config.");
       return false;
    }

    AdvancedLogger.info("[ConfigManager] Skipping to: ${candidate.name}");
    _selectedConfig = candidate;
    _safeNotifyListeners();

    if (performConnection) {
       await connectWithSmartFailover();
    }
    return true;
  }

  // --- PERSISTENCE ---
  Future<void> _initDeviceId() async {
     final info = DeviceInfoPlugin();
     try {
       if (Platform.isAndroid) {
         _currentDeviceId = 'android_${(await info.androidInfo).id}';
       } else if (Platform.isWindows) _currentDeviceId = 'windows_${(await info.windowsInfo).deviceId}';
       else if (Platform.isIOS) _currentDeviceId = 'ios_${(await info.iosInfo).identifierForVendor}';
     } catch(e) { _currentDeviceId = 'unknown'; }
  }

  Future<void> _loadConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_configsKey);
      if (str != null) {
        final list = jsonDecode(str) as List;
        allConfigs = [];
        for (var e in list) {
          try {
            // Defensively parse each config so one bad entry doesn't kill the whole list
            allConfigs.add(VpnConfigWithMetrics.fromJson(e));
          } catch (innerError) {
            AdvancedLogger.warn('[ConfigManager] Skipped corrupted config during load: $innerError');
          }
        }
        AdvancedLogger.info('[ConfigManager] Loaded ${allConfigs.length} from storage');
      }
    } catch(e) {
       AdvancedLogger.error('[ConfigManager] Load error: $e');
       // If critical failure (e.g. JSON decode), fallback to empty list but keep app running
       if (allConfigs.isEmpty) allConfigs = [];
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
    // Offload heavy sorting to isolate
    try {
      final result = await compute(_sortConfigsInIsolate, allConfigs);
      allConfigs = result['all']!;
      validatedConfigs = result['validated']!;
      favoriteConfigs = result['favorite']!;
    } catch (e) {
      AdvancedLogger.error("[ConfigManager] Sorting isolate failed: $e");
    }
  }

  void _safeNotifyListeners() {
    // Ensure UI updates are scheduled safely to prevent race conditions during build
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  Future<void> _loadBlacklist() async {
     try {
       final prefs = await SharedPreferences.getInstance();
       final list = prefs.getStringList(_blacklistKey) ?? [];
       _blockedConfigs = list.toSet();
     } catch(e) {
       AdvancedLogger.warn('[ConfigManager] Failed to load blacklist: $e');
     }
  }

  Future<void> _saveBlacklist() async {
     try {
       final prefs = await SharedPreferences.getInstance();
       await prefs.setStringList(_blacklistKey, _blockedConfigs.toList());
     } catch(e) {
       AdvancedLogger.warn('[ConfigManager] Failed to save blacklist: $e');
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

       // Logic: Fail ONLY if ping is -1 (error/timeout). Do NOT fail on high ping alone.
       if (ping == -1) {
          failureCount++;
          AdvancedLogger.warn('[Smart Monitor] Heartbeat failed. Count: $failureCount');

          if (failureCount >= 10) {
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
     await _updateLists();
     notifyListeners();
  }

  // --- SMART FAILOVER CONNECTION ---
  Future<void> connectWithSmartFailover() async {
    AdvancedLogger.info('[ConfigManager] Starting Smart Failover Connection...');
    _isGlobalStopRequested = false;

    // 1. Notify UI
    setConnected(false, status: 'Optimizing connection...');

    // 2. Get best available config
    // If user already selected a valid one, getBestConfig honors it.
    VpnConfigWithMetrics? target = await getBestConfig();

    if (target == null) {
       AdvancedLogger.warn('[ConfigManager] No configs available for connection.');
       setConnected(false, status: 'No servers available');
       return;
    }

    int attempts = 0;
    const maxAttempts = 3;
    final NativeVpnService nativeService = NativeVpnService();
    final EphemeralTester tester = EphemeralTester();

    while (attempts < maxAttempts && target != null && !_isGlobalStopRequested) {
      try {
        selectConfig(target); // Update UI selection

        // 3. Pre-flight Check (Strict - Stage 2 Connectivity)
        setConnected(false, status: 'Verifying ${target.name}...');
        final testResult = await tester.runTest(target, mode: TestMode.connectivity);

        if (testResult.funnelStage < 2 || testResult.currentPing == -1) {

             // NEW: Check if failure was INIT/PARSING error
             if (testResult.lastFailedStage != null &&
                (testResult.lastFailedStage!.contains("Init") ||
                 testResult.lastFailedStage!.contains("Stage1_ProxyInit"))) {

                 await markInvalid(target.id);
                 throw Exception("Pre-flight check failed (Invalid/Dead Config)");
             }

             // Mark regular failure and throw to trigger failover
             await markFailure(target.id);
             throw Exception("Pre-flight check failed (Connectivity)");
        }

        // Update metrics
        await updateConfigDirectly(testResult);

        if (_isGlobalStopRequested) {
          return;
        }

        // 4. Connect
        setConnected(false, status: 'Connecting to ${target.name}...');
        await nativeService.connect(target.rawConfig);

        // 5. Success
        // Mark success is assumed if command doesn't throw. Real verification is via UI listener.
        await updateConfigMetrics(target.id, connectionSuccess: true);
        await markSuccess(target.id);

        return;

      } catch (e) {
        // 6. Handle Failure
        AdvancedLogger.warn('[ConfigManager] Connection failed to ${target.name}: $e');
        // If not already marked invalid (which happens in try block), ensure markFailure is called
        // We can check if it is still alive to decide, but safe to call markFailure (it just increments)
        // unless it was marked invalid (count 99).

        // Only mark failure if it wasn't already killed
        final current = getConfigById(target.id);
        if (current != null && current.isAlive) {
           await markFailure(target.id);
        }

        if (_isGlobalStopRequested) {
          return;
        }

        // 7. Prepare next
        attempts++;
        target = await getBestConfig(); // Get NEW best

        if (target != null && target.id != _selectedConfig?.id) {
           setConnected(false, status: 'Switching to ${target.name}...');
           // Brief delay to let UI show the status
           await Future.delayed(const Duration(milliseconds: 500));
        } else if (target == null) {
           break;
        }
      }
    }

    // 8. Final Failure State
    if (!_isGlobalStopRequested) {
       setConnected(false, status: 'Connection Failed');
    }
  }
  
  // Aliases for compatibility
  Future<void> addConfig(String raw, String name) => addConfigs([raw]); 
  VpnConfigWithMetrics? getConfigById(String id) => allConfigs.firstWhereOrNull((c) => c.id == id);
}
