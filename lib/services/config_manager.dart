import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'storage_interface.dart';
import 'package:device_info_plus/device_info_plus.dart';
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
import 'network_tuning_config.dart';
import 'funnel_service.dart';

// --- TOP-LEVEL HELPER FUNCTIONS FOR ISOLATE ---

dynamic _parseJsonInIsolate(String jsonStr) {
  return jsonDecode(jsonStr);
}

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
  final emojiMap = {
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
    '🇫🇮': 'FI',
    '🇦🇹': 'AT',
    '🇳🇴': 'NO',
  };
  for (final e in emojiMap.entries) {
    if (name.contains(e.key)) {
      return e.value;
    }
  }

  final upperName = name.toUpperCase();
  final textMap = {
    'GERMAN': 'DE',
    'FRANKFURT': 'DE',
    'CLOUVIDER': 'DE',
    'HETZNER': 'DE',
    'HESSEN': 'DE',
    'UNITED STATES': 'US',
    'AMERICA': 'US',
    'UNITED KINGDOM': 'GB',
    'LONDON': 'GB',
    'ENGLAND': 'GB',
    'FRANCE': 'FR',
    'PARIS': 'FR',
    'OVH': 'FR',
    'NETHERLANDS': 'NL',
    'AMSTERDAM': 'NL',
    'HOLLAND': 'NL',
    'TURKEY': 'TR',
    'ISTANBUL': 'TR',
    'SINGAPORE': 'SG',
    'FINLAND': 'FI',
    'HELSINKI': 'FI',
    'SWEDEN': 'SE',
    'STOCKHOLM': 'SE',
    'SWITZERLAND': 'CH',
    'ZURICH': 'CH',
    'CANADA': 'CA',
    'TORONTO': 'CA',
    'RUSSIA': 'RU',
    'MOSCOW': 'RU',
    'POLAND': 'PL',
    'WARSAW': 'PL',
    'JAPAN': 'JP',
    'TOKYO': 'JP',
    'KOREA': 'KR',
    'SEOUL': 'KR',
    'HONG KONG': 'HK',
    'ITALY': 'IT',
    'SPAIN': 'ES',
    'AUSTRIA': 'AT',
    'VIENNA': 'AT',
  };
  for (final e in textMap.entries) {
    if (upperName.contains(e.key)) {
      return e.value;
    }
  }

  // Country code regex: Exclude IR to prevent remarks like 'MCI-IRAN' from showing Iran flag
  final codeRegex = RegExp(r'(?:^|[^A-Z])(US|DE|GB|UK|FR|NL|FI|TR|SG|CA|SE|CH|PL|RU|JP|KR|HK|IT|ES|AT|NO)(?:$|[^A-Z])');
  final match = codeRegex.firstMatch(upperName);
  if (match != null) {
    final code = match.group(1);
    if (code == 'UK') return 'GB';
    return code;
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

  StorageInterface storage = SecureStorage();

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
  VpnConfigWithMetrics? get fastestValidatedConfig {
    if (validatedConfigs.isEmpty) return null;
    VpnConfigWithMetrics? best;
    for (final c in validatedConfigs) {
      if (c.currentPing <= 0) continue;
      if (best == null || c.currentPing < best.currentPing) {
        best = c;
      }
    }
    return best ?? (validatedConfigs.isNotEmpty ? validatedConfigs.first : null);
  }
  List<VpnConfigWithMetrics> favoriteConfigs = [];
  List<VpnConfigWithMetrics> get gamingConfigs =>
      validatedConfigs.where((c) => c.isGamingOptimized).toList()
        ..sort((a, b) => a.currentPing.compareTo(b.currentPing));
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
  Timer? _saveDebounceTimer; // For debouncing disk I/O on rapid metric changes
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

  final bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  bool _isAutoSwitchEnabled = true;
  bool get isAutoSwitchEnabled => _isAutoSwitchEnabled;
  set isAutoSwitchEnabled(bool value) {
    _isAutoSwitchEnabled = value;
    _saveAutoSwitchSetting();
    _safeNotifyListeners();
  }

  bool _isKillSwitchEnabled = false;
  bool get isKillSwitchEnabled => _isKillSwitchEnabled;
  set isKillSwitchEnabled(bool value) {
    _isKillSwitchEnabled = value;
    _saveKillSwitchSetting();
    _safeNotifyListeners();
  }

  List<String> _splitTunnelingPackages = [];
  List<String> get splitTunnelingPackages => _splitTunnelingPackages;
  set splitTunnelingPackages(List<String> value) {
    _splitTunnelingPackages = value;
    _saveSplitTunnelingPackages();
    _safeNotifyListeners();
  }

  void toggleSplitTunnelingPackage(String packageName) {
    if (_splitTunnelingPackages.contains(packageName)) {
      _splitTunnelingPackages.remove(packageName);
    } else {
      _splitTunnelingPackages.add(packageName);
    }
    _saveSplitTunnelingPackages();
    _safeNotifyListeners();
  }

  void setSplitTunnelingPackages(List<String> packages) {
    _splitTunnelingPackages = List<String>.from(packages);
    _saveSplitTunnelingPackages();
    _safeNotifyListeners();
  }

  bool isPackageExcluded(String packageName) {
    return _splitTunnelingPackages.contains(packageName);
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
        final wasActive = _isConnected;
        setConnected(false, status: status);

        // Check if we should auto-heal (only if unexpectedly dropped from an active connection)
        if (!userInitiatedDisconnect && isAutoSwitchEnabled && wasActive) {
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
    _safeNotifyListeners();
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
    unawaited(_saveAllConfigs()); // Ensure disk write doesn't block UI
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

    // Cache current lists to avoid O(N*M) map/toList inside the loop
    List<String> currentBlockedHashes = _blockedConfigs.toList();
    List<String> currentExistingConfigs =
        allConfigs.map((c) => c.rawConfig.trim()).toList();

    // Process in chunks to avoid Isolate memory overload
    for (int i = 0; i < configStrings.length; i += batchSize) {
      final chunk = configStrings.sublist(
        i,
        (i + batchSize > configStrings.length)
            ? configStrings.length
            : i + batchSize,
      );

      final args = {
        'configStrings': chunk,
        'blockedHashes': currentBlockedHashes,
        'checkBlacklist': checkBlacklist,
        'existingConfigs': currentExistingConfigs,
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
          currentBlockedHashes = _blockedConfigs.toList();
          await _saveBlacklist();
          AdvancedLogger.info(
            "[ConfigManager] Manual overwrite: Removed ${hashesToRemove.length} configs from blacklist.",
          );
        }

        // Add New Configs
        if (newConfigs.isNotEmpty) {
          allConfigs.addAll(newConfigs);
          currentExistingConfigs.addAll(
            newConfigs.map((c) => c.rawConfig.trim()),
          );
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
      final updated = allConfigs[index].updateMetrics(
        deviceId: _currentDeviceId,
        ping: ping,
        speed: speed,
        connectionSuccess: connectionSuccess ?? false,
      );
      allConfigs[index] = updated;

      // Localized update for other lists to avoid recreation and maintain invariants
      final valIndex = validatedConfigs.indexWhere((c) => c.id == id);
      if (updated.isValidated) {
        if (valIndex != -1) {
          validatedConfigs[valIndex] = updated;
        } else {
          validatedConfigs.add(updated);
        }
      } else {
        if (valIndex != -1) {
          validatedConfigs.removeAt(valIndex);
        }
      }

      final favIndex = favoriteConfigs.indexWhere((c) => c.id == id);
      if (updated.isFavorite) {
        if (favIndex != -1) {
          favoriteConfigs[favIndex] = updated;
        } else {
          favoriteConfigs.add(updated);
        }
      } else {
        if (favIndex != -1) {
          favoriteConfigs.removeAt(favIndex);
        }
      }

      // Don't sort immediately, use throttling
      notifyListenersThrottled();
    }
  }

  Future<void> updateConfigDirectly(VpnConfigWithMetrics config) async {
    final index = allConfigs.indexWhere((c) => c.id == config.id);
    if (index != -1) {
      allConfigs[index] = config;

      final valIndex = validatedConfigs.indexWhere((c) => c.id == config.id);
      if (config.isValidated) {
        if (valIndex != -1) {
          validatedConfigs[valIndex] = config;
        } else {
          validatedConfigs.add(config);
        }
        validatedConfigs.sort((a, b) {
          if (a.currentPing > 0 && b.currentPing > 0) {
            return a.currentPing.compareTo(b.currentPing);
          } else if (a.currentPing > 0) {
            return -1;
          } else if (b.currentPing > 0) {
            return 1;
          }
          return b.score.compareTo(a.score);
        });
      } else {
        if (valIndex != -1) {
          validatedConfigs.removeAt(valIndex);
        }
      }

      final favIndex = favoriteConfigs.indexWhere((c) => c.id == config.id);
      if (config.isFavorite) {
        if (favIndex != -1) {
          favoriteConfigs[favIndex] = config;
        } else {
          favoriteConfigs.add(config);
        }
      } else {
        if (favIndex != -1) {
          favoriteConfigs.removeAt(favIndex);
        }
      }
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
      unawaited(_saveAllConfigs());
      _safeNotifyListeners();
    }
  }

  Future<void> markFailure(String id) async {
    final index = allConfigs.indexWhere((c) => c.id == id);
    if (index != -1) {
      final newFailureCount = allConfigs[index].failureCount + 1;
      final shouldKill = newFailureCount >= 3;
      allConfigs[index] = allConfigs[index].copyWith(
        failureCount: newFailureCount,
        isAlive: !shouldKill,
        funnelStage: shouldKill ? 0 : allConfigs[index].funnelStage,
        ping: shouldKill ? -1 : allConfigs[index].currentPing,
      );
      await _updateLists();
      unawaited(_saveAllConfigs());
      _safeNotifyListeners();
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
      unawaited(_saveAllConfigs());
      _safeNotifyListeners();
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
      _safeNotifyListeners();
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
      if (failedTcp && c.funnelStage == 0 && c.failureCount > 0) {
        return true;
      }
      if (dead &&
          (c.currentPing == -1 ||
              c.failureCount >= 3 ||
              (!c.isAlive && c.funnelStage == 0))) {
        return true;
      }
      if (weak && c.currentPing > 1500) {
        return true; // threshold for weak config
      }
      if (untestedSpeed && c.funnelStage < 3) {
        return true;
      }
      return false;
    });

    if (allConfigs.length < initialCount) {
      if (_selectedConfig != null && !allConfigs.contains(_selectedConfig)) {
        _selectedConfig = null;
      }
      await _updateLists();
      await _saveAllConfigs();
      _safeNotifyListeners();
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
      _safeNotifyListeners();
    }
  }

  void selectConfig(VpnConfigWithMetrics? c) {
    _selectedConfig = c;
    _safeNotifyListeners();
  }

  // --- ACTIVE CONNECTION PING & NAVIGATION ---

  Future<int> measureActivePing() async {
    if (!_isConnected || _selectedConfig == null) return -1;

    final stopwatch = Stopwatch()..start();
    final timeoutSec = (12 * NetworkTuningConfig.instance.multiplier).round().clamp(10, 30);
    try {
      final client = HttpClient();
      client.findProxy = (uri) => 'PROXY 127.0.0.1:10808';
      client.connectionTimeout = Duration(seconds: timeoutSec);
      final request = await client.getUrl(Uri.parse('http://www.google.com/generate_204'));
      final response = await request.close().timeout(Duration(seconds: timeoutSec));
      client.close();

      stopwatch.stop();
      if (response.statusCode == 204 || response.statusCode == 200) {
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
    final List<VpnConfigWithMetrics> validCandidates = [];
    for (final c in list) {
      if (!c.isDead && (c.currentPing > 0 || c.funnelStage > 0)) {
        validCandidates.add(c);
      }
    }

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

    // Find current index in validCandidates and pick next sequentially
    final currentId = _selectedConfig?.id;
    VpnConfigWithMetrics? candidate;
    final currentIndex = validCandidates.indexWhere((c) => c.id == currentId);
    if (currentIndex != -1 && validCandidates.length > 1) {
      final nextIndex = (currentIndex + 1) % validCandidates.length;
      candidate = validCandidates[nextIndex];
    } else {
      for (final c in validCandidates) {
        if (c.id != currentId) {
          candidate = c;
          break;
        }
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
      await connectWithSmartFailover(
        preferredConfig: candidate,
        excludeId: currentId,
      );
    }
    return true;
  }

  // --- PERSISTENCE ---
  Future<void> _initDeviceId() async {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        _currentDeviceId = 'android_${(await info.androidInfo).id}';
      } else if (Platform.isWindows) {
        _currentDeviceId = 'windows_${(await info.windowsInfo).deviceId}';
      } else if (Platform.isIOS) {
        _currentDeviceId = 'ios_${(await info.iosInfo).identifierForVendor}';
      }
    } catch (e) {
      _currentDeviceId = 'unknown';
    }
  }

  static String _encodeStringListInIsolate(List<String> list) {
    return jsonEncode(list);
  }

  static Future<List<VpnConfigWithMetrics>> _decodeConfigsInIsolate(
    String jsonStr,
  ) async {
    final List<VpnConfigWithMetrics> configs = [];
    final list = jsonDecode(jsonStr) as List;
    for (var e in list) {
      try {
        configs.add(VpnConfigWithMetrics.fromJson(e));
      } catch (innerError) {
        AdvancedLogger.warn(
          '[ConfigManager] Skipped corrupted config during load: $innerError',
        );
      }
    }
    return configs;
  }

  Future<void> _loadConfigs() async {
    try {
      final cached = _getCache(_configsKey);
      if (cached != null) {
        allConfigs = cached as List<VpnConfigWithMetrics>;
        AdvancedLogger.info(
          '[ConfigManager] Loaded ${allConfigs.length} configs from memory cache',
        );
        return;
      }

      final str = await storage.getString(_configsKey);
      if (str != null) {
        allConfigs = await compute(_decodeConfigsInIsolate, str);
        _setCache(_configsKey, allConfigs);
        AdvancedLogger.info(
          '[ConfigManager] Loaded ${allConfigs.length} configs from storage via Isolate',
        );
      }
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Load error: $e');
      if (allConfigs.isEmpty) allConfigs = [];
    }
  }

  // Isolate entry point for encoding configs to JSON
  static Future<String> _encodeConfigsInIsolate(
    List<VpnConfigWithMetrics> configs,
  ) async {
    return jsonEncode(configs.map((e) => e.toJson()).toList());
  }

  Future<void> _saveAllConfigs({bool forceImmediate = false}) async {
    if (forceImmediate) {
      _saveDebounceTimer?.cancel();
      _saveDebounceTimer = null;
      await _executeSaveAllConfigs();
      return;
    }

    if (_saveDebounceTimer?.isActive ?? false) return;

    _saveDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
      _saveDebounceTimer = null;
      _executeSaveAllConfigs();
    });
  }

  Future<void> _executeSaveAllConfigs() async {
    try {
      // Deep copy to prevent concurrent modification exceptions during isolate execution
      final configsSnapshot = List<VpnConfigWithMetrics>.from(allConfigs);

      // Compute JSON encoding in a background isolate to prevent UI thread blockage
      compute(_encodeConfigsInIsolate, configsSnapshot).then((jsonString) {
        // Fire-and-forget saving
        storage.setString(_configsKey, jsonString).catchError((e) {
          AdvancedLogger.error('[ConfigManager] Save error: $e');
          return false;
        });
      }).catchError((e) {
        AdvancedLogger.error('[ConfigManager] Save compute error: $e');
      });
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Save setup error: $e');
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

      validatedConfigs.clear();
      favoriteConfigs.clear();
      for (final c in allConfigs) {
        if (c.isValidated) validatedConfigs.add(c);
        if (c.isFavorite) favoriteConfigs.add(c);
      }
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
        final parsed = await compute(_parseJsonInIsolate, str);
        final list = parsed as List;
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
      final encodedStr = await compute(
        _encodeStringListInIsolate,
        _blockedConfigs.toList(),
      );
      await storage.setString(_blacklistKey, encodedStr);
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
        final parsed = await compute(_parseJsonInIsolate, jsonStr);
        final List<dynamic> decoded = parsed as List<dynamic>;
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
    final encodedStr = await compute(
      _encodeStringListInIsolate,
      _splitTunnelingPackages,
    );
    await storage.setString(_splitTunnelingKey, encodedStr);
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
  Future<VpnConfigWithMetrics?> getBestConfig({
    String? excludeId,
    Set<String>? excludeIds,
  }) async {
    final Set<String> excluded = {
      if (excludeId != null) excludeId,
      ...?excludeIds,
    };

    bool isExcluded(VpnConfigWithMetrics c) => excluded.contains(c.id);

    // 1. If user explicitly selected a config and auto-switch is disabled, always honor user's choice (if not excluded)
    if (_selectedConfig != null &&
        !_isAutoSwitchEnabled &&
        !isExcluded(_selectedConfig!)) {
      return _selectedConfig;
    }

    // 2. If user selected a valid config and not excluded, honor it
    if (_selectedConfig != null &&
        _selectedConfig!.isValidated &&
        !isExcluded(_selectedConfig!)) {
      return _selectedConfig;
    }

    // 3. Priority: Valid favorites not excluded
    final validFavorites =
        favoriteConfigs.where((c) => c.isValidated && !isExcluded(c)).toList();
    if (validFavorites.isNotEmpty) {
      validFavorites.sort((a, b) => b.calculatedScore.compareTo(a.calculatedScore));
      return validFavorites.first;
    }

    // 4. Priority: Fastest validated config not excluded
    final candidates = validatedConfigs.where((c) => !isExcluded(c)).toList();
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.calculatedScore.compareTo(a.calculatedScore));
      return candidates.first;
    }

    // 5. If user had selected any config that is not excluded
    if (_selectedConfig != null && !isExcluded(_selectedConfig!)) {
      return _selectedConfig;
    }

    // 6. Any other alive config not excluded
    final fallbackAlive =
        allConfigs.where((c) => c.isAlive && !isExcluded(c)).toList();
    if (fallbackAlive.isNotEmpty) {
      fallbackAlive.sort((a, b) => b.calculatedScore.compareTo(a.calculatedScore));
      return fallbackAlive.first;
    }

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
    _safeNotifyListeners();
  }

  void stopSession() {
    _sessionTimer?.cancel();
  }

  int _consecutivePingFailures = 0;

  // --- EVENT-DRIVEN SMART MONITOR ---
  Future<void> evaluateAutoSwitch(int currentPing) async {
    if (!isAutoSwitchEnabled || !_isConnected) return;

    // Reset failure counter if ping is healthy
    if (currentPing > 0 && currentPing <= 400) {
      _consecutivePingFailures = 0;
      return;
    }

    if (currentPing == -1) {
      _consecutivePingFailures++;
      if (_consecutivePingFailures < 2) {
        AdvancedLogger.info(
          '[ConfigManager] Active ping timeout recorded (attempt $_consecutivePingFailures/2). Waiting before auto-switch.',
        );
        return;
      }
    }

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
      _consecutivePingFailures = 0;
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
    // Priority 2: Best Validated Config (rotate sequentially)
    else if (validatedConfigs.isNotEmpty) {
      final curIdx = validatedConfigs.indexWhere((c) => c.id == _selectedConfig?.id);
      if (curIdx != -1 && validatedConfigs.length > 1) {
        nextBest = validatedConfigs[(curIdx + 1) % validatedConfigs.length];
      } else {
        nextBest = validatedConfigs.firstWhereOrNull(
          (c) => c.id != _selectedConfig?.id,
        );
      }
    }

    if (nextBest != null) {
      AdvancedLogger.info(
        '[Smart Monitor] Switching to config: ${nextBest.name}',
      );
      _selectedConfig = nextBest;
      _safeNotifyListeners();
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
    _safeNotifyListeners();
  }

  // --- SMART FAILOVER CONNECTION ---
  Future<void> connectWithSmartFailover({
    VpnConfigWithMetrics? preferredConfig,
    String? excludeId,
    Set<String>? excludeIds,
  }) async {
    userInitiatedDisconnect = false;
    isConnectionCancelled = false;
    AdvancedLogger.info(
      '[ConfigManager] Starting Smart Failover Connection...',
    );
    _isGlobalStopRequested = false;

    // Stop background funnel tests so ephemeral native testers do not collide with live tunnel
    try {
      FunnelService().stop();
    } catch (_) {}

    final Set<String> attemptedIds = {
      if (excludeId != null) excludeId,
      ...?excludeIds,
    };

    // 1. Notify UI
    setConnected(false, status: 'Optimizing connection...');

    // 2. Get target config: preferredConfig takes highest priority, then _selectedConfig (if not excluded), then getBestConfig(excludeIds)
    VpnConfigWithMetrics? target;
    if (preferredConfig != null && !attemptedIds.contains(preferredConfig.id)) {
      target = preferredConfig;
    } else if (_selectedConfig != null &&
        !attemptedIds.contains(_selectedConfig!.id) &&
        _selectedConfig!.isValidated) {
      target = _selectedConfig;
    } else {
      target = await getBestConfig(excludeIds: attemptedIds);
    }

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
      attemptedIds.add(target.id);
      try {
        selectConfig(target); // Update UI selection

        // 3. Pre-flight Check with FAST LANE logic
        setConnected(false, status: 'Verifying ${target.name}...');

        final bool isFastLane = target.isValidated &&
            target.currentPing > 0 &&
            target.lastTestedAt != null &&
            DateTime.now().difference(target.lastTestedAt!).inMinutes < 45;

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
            if (testResult.failureReason != null && testResult.failureReason!.contains('VPN Permission Required')) {
              AdvancedLogger.error("VPN permission required. Aborting pre-flight checks.");
              setConnected(false, status: 'Disconnected');
              return;
            }

            AdvancedLogger.warn(
              "[ConfigManager] Pre-flight check inconclusive for ${target.name} (${testResult.failureReason}). Proceeding directly with native tunnel.",
            );
          } else {
            await updateConfigDirectly(testResult);
          }
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
            splitTunnelingPackages: _splitTunnelingPackages,
          );

          // Wait for CONNECTED state with dynamic timeout
          final connectTimeoutSec = NetworkTuningConfig.instance.connectWaitTimeoutSec;
          await nativeService.connectionStatusStream
              .firstWhere(
            (status) => status == 'CONNECTED' || status.startsWith('ERROR'),
          )
              .timeout(
            Duration(seconds: connectTimeoutSec),
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

        // Only mark failure if it wasn't already killed and is not a local startup error
        final current = getConfigById(target.id);
        if (current != null && current.isAlive) {
          final errStr = e.toString();
          if (!errStr.contains('START_FAILED') &&
              !errStr.contains('PERMISSION') &&
              !errStr.contains('Invalid Config')) {
            await markFailure(target.id);
          } else {
            AdvancedLogger.warn(
              '[ConfigManager] Skipping markFailure for ${target.name} due to local system/config error: $e',
            );
          }
        }

        if (_isGlobalStopRequested || !_isAutoSwitchEnabled) {
          break;
        }

        // 7. Prepare next (excluding all attempted IDs)
        attempts++;
        target = await getBestConfig(excludeIds: attemptedIds);

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

    // Stop background funnel tests so ephemeral native testers do not collide with live tunnel
    try {
      FunnelService().stop();
    } catch (_) {}

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
        splitTunnelingPackages: _splitTunnelingPackages,
      );

      // Wait for CONNECTED state with dynamic timeout
      final connectTimeoutSec = NetworkTuningConfig.instance.connectWaitTimeoutSec;
      await nativeService.connectionStatusStream
          .firstWhere(
        (status) => status == 'CONNECTED' || status.startsWith('ERROR'),
      )
          .timeout(
        Duration(seconds: connectTimeoutSec),
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
