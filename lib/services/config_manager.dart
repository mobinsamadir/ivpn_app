import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'storage_interface.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart'; // Event-Driven
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart'; // Import crypto for MD5
import '../models/vpn_config_with_metrics.dart';
import '../utils/advanced_logger.dart';
import 'time_wallet_service.dart';
import '../utils/connectivity_utils.dart';
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
  } catch (_) {}

  // Fallback name
  final type = raw.split('://').first.toUpperCase();
  return '$type Server ${DateTime.now().millisecondsSinceEpoch % 1000}';
}

String? _extractCountryCode(String name) {
  final map = {
    '🇺🇸': 'US',
    '🇩🇪': 'DE',
    '🇬🇧': 'GB',
    '🇫🇷': 'FR',
    '🇯🇵': 'JP',
    '🇨🇦': 'CA',
    '🇦🇺': 'AU',
    '🇳🇱': 'NL',
    '🇸🇪': 'SE',
    '🇨🇭': 'CH',
    '🇸🇬': 'SG',
    '🇭🇰': 'HK',
    '🇰🇷': 'KR',
    '🇮🇳': 'IN',
    '🇧🇷': 'BR',
    '🇹🇷': 'TR',
    '🇮🇹': 'IT',
    '🇪🇸': 'ES',
    '🇵🇱': 'PL',
    '🇷🇺': 'RU',
    '🇮🇷': 'IR',
  };
  for (final e in map.entries) {
    if (name.contains(e.key)) {
      return e.value;
    }
  }
  return null;
}

/// Isolate entry point for processing configs
Future<Map<String, dynamic>> _processConfigsInIsolate(
  Map<String, dynamic> args,
) async {
  final List<String> configStrings = args['configStrings'] as List<String>;
  final Set<String> blockedHashes =
      (args['blockedHashes'] as List).cast<String>().toSet();
  final bool checkBlacklist = args['checkBlacklist'] as bool;
  final Set<String> existingConfigs =
      (args['existingConfigs'] as List).cast<String>().toSet();
  int addedCount = args['initialAddedCount'] as int;

  final List<VpnConfigWithMetrics> newConfigs = [];
  final List<String> hashesToRemoveFromBlacklist = [];

  // Local set to avoid duplicates within the new batch
  final Set<String> batchConfigs = {};

  for (final raw in configStrings) {
    final trimmedRaw = raw.trim();
    if (trimmedRaw.isEmpty) continue;

    if (checkBlacklist) {
      if (blockedHashes.isNotEmpty) {
        final hash = md5.convert(utf8.encode(trimmedRaw)).toString();
        if (blockedHashes.contains(hash)) {
          // Silently skip blacklisted config
          continue;
        }
      }
    } else if (blockedHashes.isNotEmpty) {
      // Manual Overwrite: If adding with checkBlacklist=false, we mark hash for removal
      final hash = md5.convert(utf8.encode(trimmedRaw)).toString();
      if (blockedHashes.contains(hash)) {
        hashesToRemoveFromBlacklist.add(hash);
      }
    }

    if (existingConfigs.contains(trimmedRaw)) {
      continue;
    }
    if (batchConfigs.contains(trimmedRaw)) {
      continue;
    }

    final name = _extractServerName(trimmedRaw);
    final id = 'config_${DateTime.now().millisecondsSinceEpoch}_$addedCount';

    newConfigs.add(
      VpnConfigWithMetrics(
        id: id,
        rawConfig: trimmedRaw,
        name: name,
        countryCode: _extractCountryCode(name),
        addedDate: DateTime.now(), // Ensure addedDate is set
      ),
    );

    batchConfigs.add(trimmedRaw);
    addedCount++;
  }

  return {
    'newConfigs': newConfigs,
    'hashesToRemoveFromBlacklist': hashesToRemoveFromBlacklist,
    'addedCount': addedCount,
  };
}

class ConfigManager extends ChangeNotifier {
  // Connection state flags
  bool userInitiatedDisconnect = false;
  bool isConnectionCancelled = false;
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;

  StorageInterface storage = SharedPreferencesStorage();

  // Caching layer
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, DateTime> _cacheTtl = {};
  static const Duration _defaultTtl = Duration(minutes: 5);

  ConfigManager._internal();

  @visibleForTesting
  void setStorage(StorageInterface storageInterface) {
    storage = storageInterface;
  }

  void _setCache(String key, dynamic value) {
    _memoryCache[key] = value;
    _cacheTtl[key] = DateTime.now().add(_defaultTtl);
  }

  dynamic _getCache(String key) {
    if (_memoryCache.containsKey(key) && _cacheTtl.containsKey(key)) {
      if (DateTime.now().isBefore(_cacheTtl[key]!)) {
        return _memoryCache[key];
      } else {
        _memoryCache.remove(key);
        _cacheTtl.remove(key);
      }
    }
    return null;
  }

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
  bool _hasPendingUpdates = false; // Flag for buffered updates

  // Global Kill Switch
  bool _isGlobalStopRequested = false;
  bool get isGlobalStopRequested => _isGlobalStopRequested;

  // Auto-Healing Guardrails
  int _consecutiveFailoverCount = 0;

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

  bool _isKillSwitchEnabled = false;
  bool get isKillSwitchEnabled => _isKillSwitchEnabled;
  set isKillSwitchEnabled(bool value) {
    _isKillSwitchEnabled = value;
    _saveKillSwitchSetting();
    notifyListeners();
  }

  List<String> _splitTunnelingPackages = [];
  List<String> get splitTunnelingPackages => _splitTunnelingPackages;
  set splitTunnelingPackages(List<String> value) {
    _splitTunnelingPackages = value;
    _saveSplitTunnelingPackages();
    notifyListeners();
  }

  // --- CONSTANTS ---
  static const String _configsKey = 'vpn_configs';
  static const String _blacklistKey = 'config_blacklist';
  static const String _autoSwitchKey = 'auto_switch_enabled';
  static const String _killSwitchKey = 'kill_switch_enabled';
  static const String _splitTunnelingKey = 'split_tunneling_packages';

  // --- INITIALIZATION ---
  Future<void> init() async {
    AdvancedLogger.info('[ConfigManager] Initializing...');
    await _initDeviceId();
    await _loadAutoSwitchSetting();
    await _loadKillSwitchSetting();
    await _loadSplitTunnelingPackages();
    await _loadBlacklist();
    await _loadConfigs();
    await _updateLists();

    // Event-Driven Network Listener
    // Time Wallet Enforced Disconnection Listener
    TimeWalletService().addListener(() {
      if (isConnected && !TimeWalletService().hasTime) {
        AdvancedLogger.warn(
          "[ConfigManager] Time Wallet expired! Enforcing disconnect.",
        );
        disconnectVpn();
      }
    });

    // PASSIVE EVENT-DRIVEN AUTO-HEALING
    NativeVpnService().connectionStatusStream.listen((status) async {
      _connectionStatus = status;

      if (status == 'CONNECTED') {
        _consecutiveFailoverCount = 0; // Reset on success
        setConnected(true, status: status);
      } else if (status == 'DISCONNECTED' || status.startsWith('ERROR')) {
        setConnected(false, status: status);

        // Check if we should auto-heal
        if (!userInitiatedDisconnect && isAutoSwitchEnabled) {
          final timeWallet = TimeWalletService();
          if (!timeWallet.hasTime) {
            AdvancedLogger.info("[Auto-Heal] Skipped: Time Wallet expired.");
            return;
          }

          if (!await ConnectivityUtils.hasInternet()) {
            AdvancedLogger.info(
              "[Auto-Heal] Skipped: No physical internet connection.",
            );
            return;
          }

          if (_consecutiveFailoverCount >= 3) {
            AdvancedLogger.warn(
              "[Auto-Heal] Max retry limit reached (3). Stopping.",
            );
            setConnected(false, status: 'Connection Lost');
            return;
          }

          _consecutiveFailoverCount++;
          AdvancedLogger.info(
            "[Auto-Heal] Attempt $_consecutiveFailoverCount: Triggering silent failover...",
          );

          connectWithSmartFailover();
        }
      } else {
        setConnected(_isConnected, status: status);
      }
    });

    Connectivity().onConnectivityChanged.listen((_) async {
      if (_isConnected) {
        AdvancedLogger.info(
          "[ConfigManager] Network state changed. Verifying connectivity...",
        );
        // Small delay to let network settle
        await Future.delayed(const Duration(seconds: 2));
        await measureActivePing();
      }
    });

    AdvancedLogger.info(
      '[ConfigManager] Initialization complete. Loaded ${allConfigs.length} configs.',
    );
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
    userInitiatedDisconnect = true;
    isConnectionCancelled = true;
    _isGlobalStopRequested = true;
    cancelScan();
    stopSmartMonitor();
    if (stopVpnCallback != null) {
      await stopVpnCallback!();
    }
    setConnected(false, status: 'Disconnected');
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
  Future<int> addConfigs(
    List<String> configStrings, {
    bool checkBlacklist = true,
  }) async {
    AdvancedLogger.info(
      '[ConfigManager] Starting to process ${configStrings.length} configs in batches...',
    );

    int totalAdded = 0;
    int initialAddedCount = 0;
    final int batchSize = 100;

    // Process in chunks to avoid Isolate memory overload
    for (int i = 0; i < configStrings.length; i += batchSize) {
      final chunk = configStrings.skip(i).take(batchSize).toList();

      final args = {
        'configStrings': chunk,
        'blockedHashes': _blockedConfigs.toList(),
        'checkBlacklist': checkBlacklist,
        'existingConfigs': allConfigs.map((c) => c.rawConfig.trim()).toList(),
        'initialAddedCount': initialAddedCount,
      };

      try {
        final result = await compute(_processConfigsInIsolate, args);

        final newConfigs = result['newConfigs'] as List<VpnConfigWithMetrics>;
        final hashesToRemove =
            result['hashesToRemoveFromBlacklist'] as List<String>;
        initialAddedCount = result['addedCount'] as int;

        // Update Blacklist
        if (hashesToRemove.isNotEmpty) {
          _blockedConfigs.removeAll(hashesToRemove);
          await _saveBlacklist();
          AdvancedLogger.info(
            "[ConfigManager] Manual overwrite: Removed ${hashesToRemove.length} configs from blacklist.",
          );
        }

        // Add New Configs
        if (newConfigs.isNotEmpty) {
          allConfigs.addAll(newConfigs);
          totalAdded += newConfigs.length;
        }
      } catch (e) {
        AdvancedLogger.error('[ConfigManager] Failed to process chunk: $e');
      }
    }

    if (totalAdded > 0) {
      await _updateLists();
      await _saveAllConfigs();
      _safeNotifyListeners();
      AdvancedLogger.info(
        '[ConfigManager] Successfully added $totalAdded configs via batched Isolates.',
      );
    }

    return totalAdded;
  }

  Future<void> updateConfigMetrics(
    String id, {
    int? ping,
    double? speed,
    bool? connectionSuccess,
  }) async {
    final index = allConfigs.indexWhere((c) => c.id == id);
    if (index != -1) {
      // Update in-place
      allConfigs[index] = allConfigs[index].updateMetrics(
        deviceId: _currentDeviceId,
        ping: ping,
        speed: speed,
        connectionSuccess: connectionSuccess ?? false,
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
        isAlive: true,
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
        isAlive: false,
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
      AdvancedLogger.warn(
        "[ConfigManager] Marking config invalid (Parsing/Init Error): ${allConfigs[index].name}",
      );
      allConfigs[index] = allConfigs[index].copyWith(
        failureCount: 99, // High penalty
        isAlive: false,
        lastFailedStage: "Invalid_Config",
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
      AdvancedLogger.info(
        "[ConfigManager] Config deleted and blacklisted: ${config.name} ($hash)",
      );

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
  Future<int> removeConfigs({
    bool failedTcp = false,
    bool dead = false,
    bool weak = false,
    bool untestedSpeed = false,
  }) async {
    final initialCount = allConfigs.length;
    allConfigs.removeWhere((c) {
      if (failedTcp && c.funnelStage == 0 && c.failureCount > 0) return true;
      if (dead &&
          (c.currentPing == -1 ||
              c.failureCount >= 3 ||
              (!c.isAlive && c.funnelStage == 0))) return true;
      if (weak && c.currentPing > 1500)
        return true; // threshold for weak config
      if (untestedSpeed && c.funnelStage < 3) return true;
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
        isFavorite: !allConfigs[index].isFavorite,
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
      final response = await http
          .head(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));

      stopwatch.stop();
      if (response.statusCode == 200) {
        final ping = stopwatch.elapsedMilliseconds;
        // Update metrics directly
        await updateConfigMetrics(
          _selectedConfig!.id,
          ping: ping,
          connectionSuccess: true,
        );
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

    final currentIndex = currentList.indexWhere(
      (c) => c.id == _selectedConfig!.id,
    );
    if (currentIndex == -1) return currentList.first;

    return currentList[(currentIndex + 1) % currentList.length];
  }

  Future<bool> skipToNext({
    List<VpnConfigWithMetrics>? sourceList,
    bool performConnection = true,
  }) async {
    final list = sourceList ??
        (validatedConfigs.isNotEmpty ? validatedConfigs : allConfigs);
    if (list.isEmpty) return false;

    // Filter out obviously dead configs
    final validCandidates = list
        .where((c) => !c.isDead && (c.currentPing > 0 || c.funnelStage > 0))
        .toList();

    if (validCandidates.isEmpty) {
      AdvancedLogger.warn(
        "[ConfigManager] Smart Skip: No valid candidates found.",
      );
      return false;
    }

    // Sort by calculated score descending (best first)
    validCandidates.sort(
      (a, b) => b.calculatedScore.compareTo(a.calculatedScore),
    );

    // Find best candidate that isn't the currently selected one
    VpnConfigWithMetrics? candidate;
    for (final c in validCandidates) {
      if (c.id != _selectedConfig?.id) {
        candidate = c;
        break;
      }
    }

    // If candidate is still null, it means the only valid candidate is the current one
    if (candidate == null) {
      AdvancedLogger.info(
        "[ConfigManager] Smart Skip: Already on the only valid config.",
      );
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
      } else if (Platform.isWindows)
        _currentDeviceId = 'windows_${(await info.windowsInfo).deviceId}';
      else if (Platform.isIOS)
        _currentDeviceId = 'ios_${(await info.iosInfo).identifierForVendor}';
    } catch (e) {
      _currentDeviceId = 'unknown';
    }
  }

  Future<void> _loadConfigs() async {
    try {
      final str = await storage.getString(_configsKey);
      if (str != null) {
        final list = jsonDecode(str) as List;
        allConfigs = [];
        for (var e in list) {
          try {
            // Defensively parse each config so one bad entry doesn't kill the whole list
            allConfigs.add(VpnConfigWithMetrics.fromJson(e));
          } catch (innerError) {
            AdvancedLogger.warn(
              '[ConfigManager] Skipped corrupted config during load: $innerError',
            );
          }
        }
        AdvancedLogger.info(
          '[ConfigManager] Loaded ${allConfigs.length} from storage',
        );
      }
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Load error: $e');
      // If critical failure (e.g. JSON decode), fallback to empty list but keep app running
      if (allConfigs.isEmpty) allConfigs = [];
    }
  }

  Future<void> _saveAllConfigs() async {
    try {
      await storage.setString(
        _configsKey,
        jsonEncode(allConfigs.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Save error: $e');
    }
  }

  Future<void> _updateLists() async {
    try {
      int compareScore(VpnConfigWithMetrics a, VpnConfigWithMetrics b) {
        final scoreCmp = b.score.compareTo(a.score);
        if (scoreCmp != 0) return scoreCmp;
        return b.addedDate.compareTo(a.addedDate);
      }

      allConfigs.sort(compareScore);
      validatedConfigs = allConfigs.where((c) => c.isValidated).toList();
      favoriteConfigs = allConfigs.where((c) => c.isFavorite).toList();
    } catch (e) {
      AdvancedLogger.error("[ConfigManager] Sorting failed: $e");
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
      final str = await storage.getString(_blacklistKey);
      if (str != null) {
        final list = jsonDecode(str) as List;
        _blockedConfigs = list.cast<String>().toSet();
      } else {
        _blockedConfigs = <String>{};
      }
    } catch (e) {
      AdvancedLogger.warn('[ConfigManager] Failed to load blacklist: $e');
    }
  }

  Future<void> _saveBlacklist() async {
    try {
      await storage.setString(
          _blacklistKey, jsonEncode(_blockedConfigs.toList()));
    } catch (e) {
      AdvancedLogger.warn('[ConfigManager] Failed to save blacklist: $e');
    }
  }

  Future<void> _loadAutoSwitchSetting() async {
    _isAutoSwitchEnabled = await storage.getBool(_autoSwitchKey) ?? true;
  }

  Future<void> _saveAutoSwitchSetting() async {
    await storage.setBool(_autoSwitchKey, _isAutoSwitchEnabled);
  }

  Future<void> _loadKillSwitchSetting() async {
    _isKillSwitchEnabled = await storage.getBool(_killSwitchKey) ?? false;
  }

  Future<void> _saveKillSwitchSetting() async {
    await storage.setBool(_killSwitchKey, _isKillSwitchEnabled);
  }

  Future<void> _loadSplitTunnelingPackages() async {
    final cached = _getCache(_splitTunnelingKey);
    if (cached != null) {
      _splitTunnelingPackages = cached;
      return;
    }
    final jsonStr = await storage.getString(_splitTunnelingKey);
    if (jsonStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        _splitTunnelingPackages = decoded.cast<String>();
        _setCache(_splitTunnelingKey, _splitTunnelingPackages);
      } catch (e) {
        AdvancedLogger.error(
          '[ConfigManager] Failed to load split tunneling packages: $e',
        );
        _splitTunnelingPackages = [];
        _setCache(_splitTunnelingKey, _splitTunnelingPackages);
      }
    } else {
      _splitTunnelingPackages = [];
      _setCache(_splitTunnelingKey, _splitTunnelingPackages);
    }
  }

  Future<void> _saveSplitTunnelingPackages() async {
    _setCache(_splitTunnelingKey, _splitTunnelingPackages);
    await storage.setString(
        _splitTunnelingKey, jsonEncode(_splitTunnelingPackages));
  }

  Future<void> switchConfig(VpnConfigWithMetrics newConfig) async {
    AdvancedLogger.info('[ConfigManager] Switching configuration safely...');
    userInitiatedDisconnect = true;
    isConnectionCancelled = true;

    // 1. Issue the disconnect
    final NativeVpnService nativeService = NativeVpnService();
    await nativeService.disconnect();

    // 2. Wait securely until the status is actually DISCONNECTED
    try {
      await nativeService.connectionStatusStream
          .firstWhere((status) => status == 'DISCONNECTED')
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      AdvancedLogger.warn(
        '[ConfigManager] Timeout waiting for DISCONNECTED state during switch. Proceeding anyway...',
      );
    }

    // 3. Initiate new connection
    await connectWithSmartFailover();
  }

  // --- UI & LEGACY COMPATIBILITY METHODS ---
  Future<VpnConfigWithMetrics?> getBestConfig() async {
    if (_selectedConfig != null && _selectedConfig!.isValidated)
      return _selectedConfig;
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

  void stopSession() {
    _sessionTimer?.cancel();
  }

  // --- EVENT-DRIVEN SMART MONITOR ---
  Future<void> evaluateAutoSwitch(int currentPing) async {
    if (!isAutoSwitchEnabled || !_isConnected) return;

    // Thresholds: >400ms is panic, must be >150ms better to switch
    const int panicThreshold = 400;
    const int improvementThreshold = 150;

    bool needsSwitch = false;

    // 1. Check current status
    if (currentPing == -1 || currentPing > panicThreshold) {
      // 2. Check for better options
      if (validatedConfigs.isNotEmpty) {
        final best = validatedConfigs.first;
        // Avoid switching to self
        if (best.id == _selectedConfig?.id) return;

        if (currentPing == -1 ||
            (best.currentPing > 0 &&
                (currentPing - best.currentPing) > improvementThreshold)) {
          needsSwitch = true;
        }
      } else if (reserveList.isNotEmpty) {
        needsSwitch = true;
      }
    }

    if (needsSwitch) {
      AdvancedLogger.warn(
        '[ConfigManager] Auto-Switch Triggered. Current Ping: $currentPing',
      );
      await _performAutoSwitch();
    }
  }

  // Legacy Polling Removed
  void startSmartMonitor() {}
  void stopSmartMonitor() {}

  Future<void> _performAutoSwitch() async {
    VpnConfigWithMetrics? nextBest;

    // Priority 1: Reserve List
    if (reserveList.isNotEmpty) {
      nextBest = reserveList.removeAt(0);
    }
    // Priority 2: Best Validated Config
    else if (validatedConfigs.isNotEmpty) {
      nextBest = validatedConfigs.firstWhereOrNull(
        (c) => c.id != _selectedConfig?.id,
      );
    }

    if (nextBest != null) {
      AdvancedLogger.info(
        '[Smart Monitor] Switching to config: ${nextBest.name}',
      );
      _selectedConfig = nextBest;
      notifyListeners();
      onAutoSwitch?.call(nextBest);
    } else {
      AdvancedLogger.info(
        '[Smart Monitor] No better configs found. Triggering Funnel...',
      );
      onTriggerFunnel?.call();
    }
  }

  Future<void> disconnectVpn() async {
    userInitiatedDisconnect = true;
    isConnectionCancelled = true;
    cancelScan();
    stopSmartMonitor();
    if (stopVpnCallback != null) {
      await stopVpnCallback!();
    }
    setConnected(false, status: 'Disconnected');
  }

  Future<void> clearAllData() async {
    await storage.remove(_configsKey);
    _selectedConfig = null;
    allConfigs.clear();
    _memoryCache.clear();
    _cacheTtl.clear();
    await _updateLists();
    notifyListeners();
  }

  // --- SMART FAILOVER CONNECTION ---
  Future<void> connectWithSmartFailover() async {
    userInitiatedDisconnect = false;
    isConnectionCancelled = false;
    AdvancedLogger.info(
      '[ConfigManager] Starting Smart Failover Connection...',
    );
    _isGlobalStopRequested = false;

    // 1. Notify UI
    setConnected(false, status: 'Optimizing connection...');

    // 2. Get best available config
    // If user already selected a valid one, getBestConfig honors it.
    VpnConfigWithMetrics? target = await getBestConfig();

    if (target == null) {
      AdvancedLogger.warn(
        '[ConfigManager] No configs available for connection.',
      );
      setConnected(false, status: 'No servers available');
      return;
    }

    int attempts = 0;
    const maxAttempts = 3;
    final NativeVpnService nativeService = NativeVpnService();
    final EphemeralTester tester = EphemeralTester();

    while (
        attempts < maxAttempts && target != null && !_isGlobalStopRequested) {
      try {
        selectConfig(target); // Update UI selection

        // 3. Pre-flight Check with FAST LANE logic
        setConnected(false, status: 'Verifying ${target.name}...');

        final bool isFastLane = target.lastTestedAt != null &&
            DateTime.now().difference(target.lastTestedAt!).inMinutes < 45 &&
            target.funnelStage >= 2 &&
            target.currentPing > 0;

        if (isFastLane) {
          AdvancedLogger.info(
            "[ConfigManager] Fast Lane: Skipping pre-flight for ${target.name} (Recent successful test)",
          );
        } else {
          final testResult = await tester.runTest(
            target,
            mode: TestMode.connectivity,
          );

          if (testResult.funnelStage < 2 || testResult.currentPing == -1) {
            if (testResult.lastFailedStage != null &&
                (testResult.lastFailedStage!.contains("Init") ||
                    testResult.lastFailedStage!.contains("Stage1_ProxyInit"))) {
              await markInvalid(target.id);
              throw Exception("Pre-flight check failed (Invalid/Dead Config)");
            }

            await markFailure(target.id);
            throw Exception("Pre-flight check failed (Connectivity)");
          }

          await updateConfigDirectly(testResult);
        }

        if (_isGlobalStopRequested) {
          return;
        }

        // 4. Connect
        setConnected(false, status: 'Connecting to ${target.name}...');
        try {
          // Initiate native connection
          await nativeService.connect(
            target.rawConfig,
            isKillSwitchEnabled: _isKillSwitchEnabled,
          );

          // Wait for CONNECTED state with strict 15-second timeout
          await nativeService.connectionStatusStream
              .firstWhere(
            (status) => status == 'CONNECTED' || status.startsWith('ERROR'),
          )
              .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('Timeout waiting for CONNECTED state');
            },
          ).then((status) {
            if (status.startsWith('ERROR')) {
              throw Exception('Native connection failed: $status');
            }
          });

          AdvancedLogger.info(
            "[ConfigManager] Native Connection Success: ${target.name}",
          );

          // 5. Success (optimistic native call success)
          await updateConfigMetrics(target.id, connectionSuccess: true);
          await markSuccess(target.id);

          return;
        } catch (e) {
          AdvancedLogger.error("Failed to connect: $e");
          rethrow;
        }
      } catch (e) {
        // Force native disconnect immediately
        await nativeService.disconnect();

        // 6. Handle Failure
        AdvancedLogger.warn(
          '[ConfigManager] Connection failed to ${target.name}: $e',
        );
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

  // --- MANUAL FORCED CONNECTION ---
  Future<void> connectManual(VpnConfigWithMetrics target) async {
    userInitiatedDisconnect = false;
    isConnectionCancelled = false;
    _isGlobalStopRequested = false;

    AdvancedLogger.info(
      '[ConfigManager] Starting Manual Connection to ${target.name}...',
    );
    setConnected(false, status: 'Connecting...');
    selectConfig(target);

    final NativeVpnService nativeService = NativeVpnService();

    try {
      // Initiate native connection
      await nativeService.connect(
        target.rawConfig,
        isKillSwitchEnabled: _isKillSwitchEnabled,
      );

      // Wait for CONNECTED state with strict 15-second timeout
      await nativeService.connectionStatusStream
          .firstWhere(
        (status) => status == 'CONNECTED' || status.startsWith('ERROR'),
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Timeout waiting for CONNECTED state');
        },
      ).then((status) {
        if (status.startsWith('ERROR')) {
          throw Exception('Native connection failed: $status');
        }
      });

      AdvancedLogger.info(
        '[ConfigManager] Manual Connection Success: ${target.name}',
      );
      // Optional: nativeService emits 'CONNECTED' and UI will catch it via stream listener.
      // But we can ensure state is updated.
      // Do not call setConnected(true) here if NativeVpnService handles broadcasting it to main UI,
      // but if we rely on it, wait for stream is sufficient.
    } catch (e) {
      AdvancedLogger.warn('[ConfigManager] Manual Connection Failed: $e');

      // Force native disconnect immediately
      await nativeService.disconnect();

      // Notify UI of failure so it can show the red banner
      setConnected(false, status: 'Connection Failed');

      // Throw exception so caller can also catch if needed
      throw Exception("Manual connection failed: $e");
    }
  }

  // Aliases for compatibility
  Future<void> addConfig(String raw, String name) => addConfigs([raw]);
  VpnConfigWithMetrics? getConfigById(String id) =>
      allConfigs.firstWhereOrNull((c) => c.id == id);
}
