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
  // Singleton instance
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();
  
  // Core lists
  List<VpnConfigWithMetrics> allConfigs = [];
  List<VpnConfigWithMetrics> validatedConfigs = [];
  List<VpnConfigWithMetrics> favoriteConfigs = [];
  
  // Device identification
  String _currentDeviceId = 'unknown';
  String get currentDeviceId => _currentDeviceId;
  
  // Current selection
  VpnConfigWithMetrics? _selectedConfig;
  VpnConfigWithMetrics? get selectedConfig => _selectedConfig;

  // Connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  String _connectionStatus = 'Ready';
  String get connectionStatus => _connectionStatus;

  // --- Session Timer State ---
  Timer? _sessionTimer;
  Duration _remainingTime = Duration.zero;
  VoidCallback? _onSessionExpiredCallback;
  
  // Refreshing state
  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  // Auto-switch state
  bool _isAutoSwitchEnabled = true;
  bool get isAutoSwitchEnabled => _isAutoSwitchEnabled;
  set isAutoSwitchEnabled(bool value) {
    _isAutoSwitchEnabled = value;
    _saveAutoSwitchSetting();
    notifyListeners();
  }

  // Storage keys
  static const String _configsKey = 'vpn_configs';
  static const String _autoSwitchKey = 'auto_switch_enabled';
  static const String _githubUrl = 'https://raw.githubusercontent.com/mobinsamadir/ivpn-servers/main/servers.txt';
  static const String _githubMirrorUrl = 'https://ghproxy.com/https://raw.githubusercontent.com/mobinsamadir/ivpn-servers/main/servers.txt';
  
  // Initialization
  Future<void> init() async {
    AdvancedLogger.info('[ConfigManager] Initializing...');

    // 1. Get device ID
    await _initDeviceId();

    // 2. Load auto-switch setting
    await _loadAutoSwitchSetting();

    // 3. Load configs from storage
    await _loadConfigs();

    // 4. If empty, try to load initial defaults OR download from GitHub
    if (allConfigs.isEmpty) {
      AdvancedLogger.info('[ConfigManager] No configs found in storage, loading initial defaults...');
      final initialConfigs = await ConfigImporter.loadInitialConfigs();
      int skippedCount = 0;
      for (var raw in initialConfigs) {
        final trimmedRaw = raw.trim();
        if (allConfigs.any((c) => c.rawConfig.trim() == trimmedRaw)) {
          skippedCount++;
          continue;
        }

        final id = 'initial_${DateTime.now().millisecondsSinceEpoch}_${allConfigs.length}';
        final name = _extractServerName(trimmedRaw);
        allConfigs.add(VpnConfigWithMetrics(
          id: id,
          rawConfig: trimmedRaw,
          name: name,
          countryCode: _extractCountryCode(name),
        ));
      }

      // If still empty (unlikely with hardcoded defaults), download from GitHub
      if (allConfigs.isEmpty) {
        await downloadConfigsFromGitHub();
      } else {
        await _saveAllConfigs();
        _updateLists();
        notifyListeners();
      }
    }

    // 5. Force list population
    _updateLists();

    // 6. Perform auto-test on eligible configs
    await _performAutoTest();

    // 7. Start background startup checks (refresh & test all configs)
    _performStartupChecks(); // Don't await - run in background

    AdvancedLogger.info('[ConfigManager] Ready. Device: $_currentDeviceId');
    AdvancedLogger.info('[ConfigManager] Loaded ${allConfigs.length} configs');
    AdvancedLogger.info('[ConfigManager] Auto-switch enabled: $_isAutoSwitchEnabled');

    // Force config update in the background without blocking UI
    downloadConfigsFromGitHub(); // Fire and forget
  }

  // Perform auto-test on configs that are eligible for auto-test
  Future<void> _performAutoTest() async {
    try {
      AdvancedLogger.info('[ConfigManager] Starting auto-test for eligible configs...');

      // Filter configs that are eligible for auto-test (no numbers in name)
      final eligibleConfigs = allConfigs.where((config) => config.isEligibleForAutoTest).toList();

      if (eligibleConfigs.isEmpty) {
        AdvancedLogger.info('[ConfigManager] No configs eligible for auto-test');
        return;
      }

      AdvancedLogger.info('[ConfigManager] Found ${eligibleConfigs.length} configs eligible for auto-test');

      // Test each eligible config
      for (final config in eligibleConfigs) {
        try {
          // Use the latency service to test the config
          // For now, we'll just use the existing metrics or skip to the next
          // In a real implementation, we'd need to have access to the latency service

          // For demonstration purposes, we'll just log that we're testing
          AdvancedLogger.info('[ConfigManager] Auto-testing config: ${config.name}');

          // In a real implementation, we would call the actual testing method
          // await _testConfig(config);
        } catch (e) {
          AdvancedLogger.error('[ConfigManager] Auto-test failed for ${config.name}: $e');
          continue;
        }
      }

      AdvancedLogger.info('[ConfigManager] Auto-test completed');
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Auto-test process failed: $e');
    }
  }

  // Perform startup checks: refresh configs from GitHub and run tests on all configs
  Future<void> _performStartupChecks() async {
    try {
      AdvancedLogger.info('[ConfigManager] Starting startup checks...');

      // Refresh configs from GitHub
      await downloadConfigsFromGitHub();

      // Run tests on all configs
      await runQuickTestOnAllConfigs((log) {
        AdvancedLogger.info('[ConfigManager] Startup test: $log');
      });

      AdvancedLogger.info('[ConfigManager] Startup checks completed');
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Startup checks failed: $e');
    }
  }

  Future<void> _initDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _currentDeviceId = 'android_${androidInfo.id}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _currentDeviceId = 'ios_${iosInfo.identifierForVendor}';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        _currentDeviceId = 'windows_${windowsInfo.deviceId}';
      } else {
        _currentDeviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      AdvancedLogger.warn('[ConfigManager] Failed to get device ID: $e');
      _currentDeviceId = 'unknown_fallback';
    }
  }
  
  Future<void> _loadConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_configsKey);

      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final List<VpnConfigWithMetrics> loadedConfigs = jsonList
            .map((json) => VpnConfigWithMetrics.fromJson(json))
            .toList();
        
        // Atomic-like swap to prevent race conditions with background updates
        allConfigs = loadedConfigs;
        AdvancedLogger.info('[ConfigManager] Loaded ${allConfigs.length} configs from storage');
      } else {
        allConfigs = [];
      }
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Error loading configs: $e');
      allConfigs = [];
    }

    _updateLists();
    notifyListeners();
    printInventoryReport();
  }
  
  Future<void> _saveAllConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = allConfigs.map((c) => c.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await prefs.setString(_configsKey, jsonString);
      AdvancedLogger.debug('[ConfigManager] Saved ${allConfigs.length} configs');
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Error saving configs: $e');
    }
  }

  Future<void> _saveAutoSwitchSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoSwitchKey, _isAutoSwitchEnabled);
      AdvancedLogger.info('[ConfigManager] Saved auto-switch setting: $_isAutoSwitchEnabled');
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Error saving auto-switch setting: $e');
    }
  }

  Future<void> _loadAutoSwitchSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isAutoSwitchEnabled = prefs.getBool(_autoSwitchKey) ?? true;
      AdvancedLogger.info('[ConfigManager] Loaded auto-switch setting: $_isAutoSwitchEnabled');
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Error loading auto-switch setting: $e');
      _isAutoSwitchEnabled = true; // Default to enabled
    }
  }
  
  /// Download configs from GitHub
  Future<Map<String, int>> downloadConfigsFromGitHub() async {
    try {
      AdvancedLogger.info('[ConfigManager] Downloading configs from GitHub...');

      // Try mirror/proxy first
      String content = '';
      bool downloadSuccess = false;

      // Try primary URL (mirror/proxy)
      try {
        AdvancedLogger.info('[ConfigManager] Trying primary mirror URL: $_githubMirrorUrl');
        final response = await http.get(Uri.parse(_githubMirrorUrl)).timeout(
          const Duration(seconds: 30),
        );

        if (response.statusCode == 200) {
          try {
            content = utf8.decode(base64Decode(response.body));
            AdvancedLogger.info('[ConfigManager] Successfully decoded Base64 content from mirror');
          } catch (e) {
            content = response.body; // USE ORIGINAL TEXT
            AdvancedLogger.info('[ConfigManager] Used plain text configs (not Base64)');
          }
          downloadSuccess = true;
          // Debug log to see what content is being downloaded
          AdvancedLogger.info('📥 Content Preview: ${content.length > 200 ? content.substring(0, 200) : content}');
        } else {
          AdvancedLogger.warn('[ConfigManager] Mirror failed: HTTP ${response.statusCode}, trying backup...');
        }
      } catch (e) {
        AdvancedLogger.warn('[ConfigManager] Mirror download failed: $e, trying backup...');
      }

      // If mirror failed, try backup URL
      if (!downloadSuccess) {
        try {
          AdvancedLogger.info('[ConfigManager] Trying backup URL: $_githubUrl');
          final response = await http.get(Uri.parse(_githubUrl)).timeout(
            const Duration(seconds: 30),
          );

          if (response.statusCode == 200) {
            try {
              content = utf8.decode(base64Decode(response.body));
              AdvancedLogger.info('[ConfigManager] Successfully decoded Base64 content from backup');
            } catch (e) {
              content = response.body; // USE ORIGINAL TEXT
              AdvancedLogger.info('[ConfigManager] Used plain text configs (not Base64)');
            }
            downloadSuccess = true;
            // Debug log to see what content is being downloaded
            AdvancedLogger.info('📥 Content Preview: ${content.length > 200 ? content.substring(0, 200) : content}');
          } else {
            AdvancedLogger.error('[ConfigManager] Backup failed: HTTP ${response.statusCode}');
          }
        } catch (e) {
          AdvancedLogger.error('[ConfigManager] Backup download failed: $e');
        }
      }

      if (!downloadSuccess) {
        AdvancedLogger.error('[ConfigManager] Both mirror and backup URLs failed');
        return {'added': 0, 'skipped': 0, 'total': 0};
      }

      // Use the unified parser to extract configs
      final configUrls = parseConfigText(content);

      int addedCount = 0;
      int skippedCount = 0;

      // Create a copy of current configs to modify
      final List<VpnConfigWithMetrics> newConfigs = List.from(allConfigs);

      for (final configUrl in configUrls) {
        if (!newConfigs.any((config) => config.rawConfig == configUrl)) {
          final id = 'config_${DateTime.now().millisecondsSinceEpoch}_$addedCount';
          final name = _extractServerName(configUrl);
          final countryCode = _extractCountryCode(name);

          newConfigs.add(VpnConfigWithMetrics(
            id: id,
            rawConfig: configUrl,
            name: name,
            countryCode: countryCode,
          ));
          addedCount++;
        } else {
          skippedCount++;
        }
      }

      if (addedCount > 0) {
        // Atomic swap
        allConfigs = newConfigs;
        await _saveAllConfigs();
        _updateLists();
        notifyListeners();
        AdvancedLogger.info('[ConfigManager] Import finished: Added $addedCount new configs');
      }

      return {'added': addedCount, 'skipped': skippedCount, 'total': configUrls.length};
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Error downloading configs: $e');
      return {'added': 0, 'skipped': 0, 'total': 0};
    }
  }

  /// Unified refresh method for UI
  Future<void> refreshAllConfigs() async {
    if (_isRefreshing) return;
    
    _isRefreshing = true;
    notifyListeners();
    
    AdvancedLogger.info('[ConfigManager] Starting full refresh...');
    try {
      await downloadConfigsFromGitHub();
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }
  
  String _extractServerName(String rawConfig) {
    try {
      // Try to extract name from config URL
      final uri = Uri.parse(rawConfig);
      final fragment = uri.fragment;
      if (fragment.isNotEmpty) {
        return Uri.decodeComponent(fragment);
      }
      
      // Fallback to generic name
      final protocol = rawConfig.split('://').first.toUpperCase();
      return '$protocol Server ${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      return 'Server ${DateTime.now().millisecondsSinceEpoch}';
    }
  }
  
  String? _extractCountryCode(String name) {
    // Extract country code from emoji or text
    final countryMap = {
      '🇺🇸': 'US', '🇩🇪': 'DE', '🇬🇧': 'GB', '🇫🇷': 'FR', '🇯🇵': 'JP',
      '🇨🇦': 'CA', '🇦🇺': 'AU', '🇳🇱': 'NL', '🇸🇪': 'SE', '🇨🇭': 'CH',
      '🇸🇬': 'SG', '🇭🇰': 'HK', '🇰🇷': 'KR', '🇮🇳': 'IN', '🇧🇷': 'BR',
      '🇹🇷': 'TR', '🇮🇹': 'IT', '🇪🇸': 'ES', '🇵🇱': 'PL', '🇷🇺': 'RU',
    };
    
    for (final entry in countryMap.entries) {
      if (name.contains(entry.key)) {
        return entry.value;
      }
    }
    
    return null;
  }
  
  void _updateLists() {
    // Update validated configs
    validatedConfigs = allConfigs.where((config) => config.isValidated(_currentDeviceId)).toList();
    
    // Update favorite configs
    favoriteConfigs = allConfigs.where((config) => config.isFavorite).toList();
    
    // Sort lists by score
    validatedConfigs.sort((a, b) => b.calculatedScore.compareTo(a.calculatedScore));
    favoriteConfigs.sort((a, b) => b.calculatedScore.compareTo(a.calculatedScore));
    allConfigs.sort((a, b) => b.calculatedScore.compareTo(a.calculatedScore));
  }
  
  // Add a new config
  Future<void> addConfig(String rawConfig, String name, {String? countryCode}) async {
    // Print inventory report before adding a new item to see what was there before
    printInventoryReport();

    // Check for duplicates based on rawConfig content (trimmed)
    final trimmedRaw = rawConfig.trim();
    final existingConfig = allConfigs.where((config) => config.rawConfig.trim() == trimmedRaw).firstOrNull;

    // If config already exists, don't add it again
    if (existingConfig != null) {
      AdvancedLogger.info('[ConfigManager] Config already exists, skipping duplicate: $name');
      return;
    }

    final id = 'config_${DateTime.now().millisecondsSinceEpoch}';

    final newConfig = VpnConfigWithMetrics(
      id: id,
      rawConfig: rawConfig,
      name: name,
      countryCode: countryCode,
    );

    allConfigs.add(newConfig);
    _updateLists();
    await _saveAllConfigs(); // Crucial: Save to storage immediately after modification
    notifyListeners(); // Notify UI that data has changed

    AdvancedLogger.info('[ConfigManager] Added new config: $name');
  }
  
  /// Delete a config by ID
  Future<bool> deleteConfig(String configId) async {
    try {
      final index = allConfigs.indexWhere((c) => c.id == configId);
      if (index == -1) {
        AdvancedLogger.warn('[ConfigManager] Config not found for deletion: $configId');
        return false;
      }

      final config = allConfigs[index];
      allConfigs.removeAt(index);

      // Clear selection if deleted
      if (_selectedConfig?.id == configId) {
        _selectedConfig = null;
      }

      _updateLists();
      await _saveAllConfigs(); // Crucial: Save to storage immediately after modification
      notifyListeners(); // Notify UI that data has changed

      AdvancedLogger.info('[ConfigManager] Deleted config: ${config.name}');
      return true;
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Error deleting config: $e');
      return false;
    }
  }
  
  // Update config metrics
  Future<void> updateConfigMetrics(String configId, {
    int? ping,
    double? speed,
    bool? connectionSuccess,
  }) async {
    final index = allConfigs.indexWhere((c) => c.id == configId);
    if (index == -1) {
      AdvancedLogger.warn('[ConfigManager] Config not found for metrics update: $configId');
      return; // Guard clause: return if config not found, don't create new config
    }

    // Update the config metrics
    allConfigs[index].updateMetrics(
      _currentDeviceId,
      ping: ping,
      speed: speed,
      success: connectionSuccess,
    );

    // Atomic update: replace the config in the list to ensure UI updates
    allConfigs[index] = allConfigs[index].copyWith(
      isFavorite: allConfigs[index].isFavorite, // Preserve current favorite status
    );

    _updateLists();
    await _saveAllConfigs();
    notifyListeners(); // Notify UI that data has changed

    AdvancedLogger.debug('[ConfigManager] Updated metrics for ${allConfigs[index].name}');
  }
  
  // Toggle favorite
  Future<void> toggleFavorite(String configId) async {
    final index = allConfigs.indexWhere((c) => c.id == configId);
    if (index == -1) {
      AdvancedLogger.warn('[ConfigManager] Config not found for toggle favorite: $configId');
      return;
    }

    allConfigs[index].isFavorite = !allConfigs[index].isFavorite;

    _updateLists();
    await _saveAllConfigs();
    notifyListeners(); // Notify UI that data has changed

    AdvancedLogger.info('[ConfigManager] Toggled favorite for ${allConfigs[index].name}');
  }
  
  // Select a config
  void selectConfig(VpnConfigWithMetrics? config) {
    _selectedConfig = config;
    notifyListeners(); // Notify UI that data has changed
    AdvancedLogger.info('[ConfigManager] Selected config: ${config?.name ?? 'None'}');
  }

  /// Secure delete method with safety checks
  Future<bool> deleteConfigSecure(String configId) async {
    try {
      // Check if the config to be deleted is the currently selected config
      if (_selectedConfig?.id == configId) {
        _selectedConfig = null; // Deselect it
        AdvancedLogger.info('[ConfigManager] Deselected config before deletion: $configId');
      }

      // Note: We don't check if it's the currently connected config here
      // because the actual VPN connection logic is handled elsewhere
      // This method focuses on the config management aspect

      // Proceed with deletion
      final index = allConfigs.indexWhere((c) => c.id == configId);
      if (index == -1) {
        AdvancedLogger.warn('[ConfigManager] Config not found for deletion: $configId');
        return false;
      }

      final config = allConfigs[index];
      allConfigs.removeAt(index);

      _updateLists();
      await _saveAllConfigs();
      notifyListeners(); // Notify UI that data has changed

      AdvancedLogger.info('[ConfigManager] Successfully deleted config: ${config.name}');
      return true;
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Error deleting config: $e');
      return false;
    }
  }

  /// Delete all configs
  Future<void> deleteAllConfigs() async {
    try {
      allConfigs = []; // Atomic swap to empty list
      _selectedConfig = null; // Clear selected config
      _updateLists();
      await _saveAllConfigs(); // Save empty list to storage
      notifyListeners(); // Notify UI that data has changed

      AdvancedLogger.info('[ConfigManager] All configs deleted');
    } catch (e) {
      AdvancedLogger.error('[ConfigManager] Error deleting all configs: $e');
    }
  }
  
  // Print a full inventory report of current loaded configs
  void printInventoryReport() {
    AdvancedLogger.info('📊 ===== CONFIG INVENTORY REPORT ===== 📊');
    AdvancedLogger.info('Total Loaded: ${allConfigs.length}');

    final uniqueSet = <String>{};
    int duplicates = 0;

    for (int i = 0; i < allConfigs.length; i++) {
      final config = allConfigs[i];
      final isDuplicate = uniqueSet.contains(config.rawConfig.trim());
      if (!isDuplicate) {
        uniqueSet.add(config.rawConfig.trim());
      } else {
        duplicates++;
      }

      AdvancedLogger.info(
        'ITEM #$i: '
        'Name: "${config.name}" | '
        'Ping: ${config.currentPing}ms | '
        'Duplicate: ${isDuplicate ? "YES ⚠️" : "NO"} | '
        'RawLength: ${config.rawConfig.length}'
      );
    }

    AdvancedLogger.info('📊 SUMMARY: Unique: ${uniqueSet.length}, Real Duplicates: $duplicates');
    AdvancedLogger.info('==========================================');
  }

  // Get best config for smart connection
  Future<VpnConfigWithMetrics?> getBestConfig() async {
    AdvancedLogger.info('[ConfigManager] getBestConfig called. Total configs: ${allConfigs.length}, Selected: ${_selectedConfig?.name ?? "None"}');

    // Priority 1: Selected config
    if (_selectedConfig != null) {
      AdvancedLogger.info('[ConfigManager] Selected config: ${_selectedConfig!.name}, isValidated: ${_selectedConfig!.isValidated(_currentDeviceId)}');
      if (_selectedConfig!.isValidated(_currentDeviceId)) {
        AdvancedLogger.info('[ConfigManager] Returning selected validated config: ${_selectedConfig!.name}');
        return _selectedConfig;
      } else {
        AdvancedLogger.info('[ConfigManager] Selected config is not validated, continuing to next priority');
      }
    } else {
      AdvancedLogger.info('[ConfigManager] No selected config, checking favorites and validated configs');
    }

    // Priority 2: Favorite with good ping
    final validFavorites = favoriteConfigs.where((c) => c.isValidated(ConfigManager().currentDeviceId)).toList();
    if (validFavorites.isNotEmpty) {
      validFavorites.sort((a, b) => a.currentPing.compareTo(b.currentPing));
      AdvancedLogger.info('[ConfigManager] Returning favorite validated config: ${validFavorites.first.name}');
      return validFavorites.first;
    }

    // Priority 3: Fastest validated config
    if (validatedConfigs.isNotEmpty) {
      validatedConfigs.sort((a, b) => a.currentPing.compareTo(b.currentPing));
      AdvancedLogger.info('[ConfigManager] Returning fastest validated config: ${validatedConfigs.first.name}');
      return validatedConfigs.first;
    }

    // Priority 4: Any config (last resort)
    if (allConfigs.isNotEmpty) {
      AdvancedLogger.info('[ConfigManager] Returning first available config: ${allConfigs.first.name}');
      return allConfigs.first;
    }

    AdvancedLogger.warn('[ConfigManager] No configs available to return');
    return null;
  }
  
  // Run quick tests on all configs with Parallel Intelligence logic
  Future<VpnConfigWithMetrics?> runQuickTestOnAllConfigs(Function(String)? onLog) async {
    if (allConfigs.isEmpty) {
      return null;
    }

    VpnConfigWithMetrics? fastestConfig; // First config with ping < 1200ms
    VpnConfigWithMetrics? bestConfig; // Overall best ping
    int bestPing = 9999; // Initialize with a high value
    int fastestPing = 9999; // For eager start

    // Test all configs in parallel with eager start logic
    for (final config in allConfigs) {
      try {
        // For now, we'll use the existing metrics if available
        if (config.currentPing > 0) {
          // EAGER START: Find first config with ping < 1200ms
          if (config.currentPing < 1200 && config.currentPing < fastestPing) {
            fastestConfig = config;
            fastestPing = config.currentPing;
          }

          // Track overall best config
          if (config.currentPing < bestPing) {
            bestPing = config.currentPing;
            bestConfig = config;
          }
        }
      } catch (e) {
        // Skip configs that fail the test
        onLog?.call('Failed to test config ${config.name}: $e');
        continue;
      }
    }

    // Return the fastest config for immediate connection (if available)
    return fastestConfig ?? bestConfig;
  }

  // Clear all data
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configsKey);

    allConfigs = [];
    validatedConfigs = [];
    favoriteConfigs = [];
    _selectedConfig = null;

    notifyListeners();
    AdvancedLogger.warn('[ConfigManager] All data cleared');
  }

  // Get config by ID
  VpnConfigWithMetrics? getConfigById(String id) {
    try {
      return allConfigs.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  // --- Session Timer Getters ---
  Duration get remainingTime => _remainingTime;
  String get formattedRemainingTime {
    final minutes = _remainingTime.inMinutes.remainder(60);
    final seconds = _remainingTime.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Connection state methods
  void setConnected(bool connected, {String status = 'Connected'}) {
    _isConnected = connected;
    _connectionStatus = status;
    notifyListeners(); // Notify UI that connection state has changed
  }

  // --- Session Timer Methods ---
  void startSession([VoidCallback? onSessionExpired]) {
    stopSession(); // Stop any existing session first
    _onSessionExpiredCallback = onSessionExpired;
    _remainingTime = const Duration(hours: 1);
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remainingTime = _remainingTime - const Duration(seconds: 1);
      if (_remainingTime.isNegative) {
        _remainingTime = Duration.zero;
        // Enforce session end: disconnect when time is up
        _onSessionExpired();
        timer.cancel();
      }
      notifyListeners(); // Notify UI that timer has updated
    });
  }

  void stopSession() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _remainingTime = Duration.zero;
    notifyListeners(); // Notify UI that session has stopped
  }

  void _onSessionExpired() {
    AdvancedLogger.info('[ConfigManager] Session time expired. Disconnecting...');
    // Call the callback if provided
    _onSessionExpiredCallback?.call();
    // Show notification about session expiration
    _showSessionExpiredNotification();
  }

  void _showSessionExpiredNotification() {
    // This would typically trigger a callback to the UI layer
    // For now, we'll just log it
    AdvancedLogger.info('[ConfigManager] Session expired. Please reconnect.');
  }

  // Check if current ping is high enough to trigger auto-switch
  bool isCurrentPingHigh() {
    if (_selectedConfig != null) {
      // Consider ping high if it's greater than 2000ms or -1 (timeout)
      return _selectedConfig!.currentPing > 2000 || _selectedConfig!.currentPing == -1;
    }
    return false;
  }

  // Unified config parsing logic for both Smart Paste and Config Download
  static List<String> parseConfigText(String text) {
    // Step A: Try the existing Regex to find matches
    final regex = RegExp(r"(vmess|vless|ss|trojan)://[a-zA-Z0-9-._~:/?#[\]@!$&'()*+,;=%]+", caseSensitive: false);
    final regexMatches = regex.allMatches(text).map((match) => match.group(0)!).toList();

    // If Regex finds sufficient matches, return them after validation
    if (regexMatches.length >= 3) { // Consider "sufficient" if we find 3 or more
      return regexMatches.where((config) => ClipboardUtils.validateConfig(config)).toList();
    }

    // Step B: If Regex count is low, split text by [\r\n\s,]+ (Newlines, Spaces, Commas)
    final splitParts = text.split(RegExp(r'[\r\n\s,]+')).where((part) => part.trim().isNotEmpty).toList();

    // Step C: Filter results using ClipboardUtils.validateConfig
    final validConfigs = <String>[];
    for (final part in splitParts) {
      final trimmedPart = part.trim();
      if (ClipboardUtils.validateConfig(trimmedPart)) {
        // Avoid duplicates
        if (!validConfigs.contains(trimmedPart)) {
          validConfigs.add(trimmedPart);
        }
      }
    }

    // If split method found more configs, return those; otherwise return regex results
    return validConfigs.length > regexMatches.length
        ? validConfigs
        : regexMatches.where((config) => ClipboardUtils.validateConfig(config)).toList();
  }

  // Enhanced async method to parse configs and fetch from subscription links
  static Future<List<String>> parseAndFetchConfigs(String text) async {
    final allConfigs = <String>{};

    // Step 1: Extract direct configs using existing logic
    final directConfigs = parseConfigText(text);
    allConfigs.addAll(directConfigs);

    // Step 2: Extract subscription links
    final subLinkRegex = RegExp(r"https?://[^\s\"'<>\n\r`{}|\[\]]+", caseSensitive: false);
    final subLinks = subLinkRegex.allMatches(text)
        .map((match) => match.group(0)!)
        .where((link) => !directConfigs.any((config) => config.contains(Uri.parse(link).host)))
        .toSet();

    // Step 3: Fetch configs from each subscription link
    for (final link in subLinks) {
      try {
        AdvancedLogger.info('[ConfigManager] Attempting to fetch configs from subscription link: $link');
        
        final response = await http.get(Uri.parse(link));
        if (response.statusCode == 200) {
          final responseBody = utf8.decode(response.bodyBytes); // Handle encoding properly
          final fetchedConfigs = parseConfigText(responseBody);
          
          AdvancedLogger.info('[ConfigManager] Fetched ${fetchedConfigs.length} configs from $link');
          
          // Add fetched configs to the main list
          allConfigs.addAll(fetchedConfigs);
        } else {
          AdvancedLogger.warn('[ConfigManager] Failed to fetch from $link, status: ${response.statusCode}');
        }
      } catch (e) {
        AdvancedLogger.error('[ConfigManager] Error fetching subscription from $link: $e');
      }
    }

    return allConfigs.toList();
  }

  // Method to properly disconnect VPN
  Future<void> disconnectVpn() async {
    // In a real implementation, this would call the actual VPN service
    // to disconnect the VPN connection
    // For now, we'll just set the connection status to disconnected
    setConnected(false, status: 'Disconnected');
    stopSession();
    notifyListeners(); // Notify UI that disconnection is complete
    AdvancedLogger.info('[ConfigManager] VPN disconnected');
  }
}
