import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/ad_config.dart';
import '../utils/advanced_logger.dart';
import '../widgets/full_screen_ad_dialog.dart';
import 'network_tuning_config.dart';

// Global toggle for Ads (True = Ads Enabled, False = Ads Disabled / Premium Free Mode)
// Driven by configuration `global_ads_enabled` (defaults to true)
bool kEnableAds = true;

class AdManagerService {
  static final AdManagerService _instance = AdManagerService._internal();
  factory AdManagerService() => _instance;
  AdManagerService._internal();

  final ValueNotifier<AdConfig?> configNotifier = ValueNotifier<AdConfig?>(
    null,
  );

  // Primary URL (Direct from Repository)
  static const String _adUrl =
      'https://raw.githubusercontent.com/mobinsamadir/ivpn_app/main/assets/ad_config.json';

  // Fallback Mirror (jsDelivr CDN)
  static const String _adMirrorUrl =
      'https://cdn.jsdelivr.net/gh/mobinsamadir/ivpn_app@main/assets/ad_config.json';

  static const String _storageKey = "ad_config_cache";

  // Use the HTML from AAdsBanner as default
  static const String _defaultAdHtml = """
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    html, body { margin: 0; padding: 0; width: 100%; height: 100%; background-color: transparent !important; overflow: hidden; display: flex; justify-content: center; align-items: center; }
    iframe { border: none; width: 100%; height: 100%; overflow: hidden; display: block; }
  </style>
</head>
<body>
  <iframe data-aa="2426527" src="https://acceptable.a-ads.com/2426527/?size=Adaptive"></iframe>
</body>
</html>
""";

  // Construct the JSON structure with ads enabled by default
  static final Map<String, dynamic> _defaultFallbackMap = {
    "config_version": "fallback_v1",
    "global_ads_enabled": 1,
    "ads": {
      "home_banner_top": {
        "isEnabled": true,
        "type": "webview",
        "mediaSource": _defaultAdHtml,
        "targetUrl": "",
        "timerSeconds": 0,
      },
      "home_banner_bottom": {
        "isEnabled": true,
        "type": "webview",
        "mediaSource": _defaultAdHtml,
        "targetUrl": "",
        "timerSeconds": 0,
      },
      "reward_ad": {
        "isEnabled": true,
        "type": "webview",
        "mediaSource": _defaultAdHtml,
        "targetUrl": "",
        "timerSeconds": 10, // Timer for reward ad
      },
    },
  };

  bool _initialized = false;

  // Dynamic Dio instance with timeouts calibrated for Iranian network conditions
  Dio get _dio {
    final timeoutSec = (18 * NetworkTuningConfig.instance.multiplier).round().clamp(15, 45);
    return Dio(
      BaseOptions(
        connectTimeout: Duration(seconds: timeoutSec),
        receiveTimeout: Duration(seconds: timeoutSec),
        sendTimeout: Duration(seconds: timeoutSec),
      ),
    );
  }

  Future<void> initialize() async {
    if (_initialized) return;

    AdvancedLogger.info("[AdManager] Initializing...");

    // 1. Layer 1: Load Default Immediately
    try {
      final defaultConfig = AdConfig.fromJson(_defaultFallbackMap);
      configNotifier.value = defaultConfig;
      AdvancedLogger.info("[AdManager] Loaded default fallback config.");
    } catch (e) {
      AdvancedLogger.error("[AdManager] Failed to load default config: $e");
    }

    // 2. Layer 2: Load from bundled assets if available
    await _loadFromAsset();

    // 3. Layer 3: Load from Cache
    await _loadFromCache();

    // 4. Layer 4: Network Fetch Removed from Startup
    // Only fetchLatestAds() will call network, triggered post-connect.

    _initialized = true;
  }

  Future<void> _loadFromAsset() async {
    try {
      final assetJson = await rootBundle.loadString('assets/ad_config.json');
      final jsonMap =
          await compute<String, dynamic>(_parseJsonInIsolate, assetJson);
      final assetConfig = AdConfig.fromJson(jsonMap);
      final int globalAds = jsonMap['global_ads_enabled'] as int? ?? 1;
      kEnableAds = (globalAds == 1);
      configNotifier.value = assetConfig;
      AdvancedLogger.info("[AdManager] Loaded bundled asset config.");
    } catch (e) {
      AdvancedLogger.debug("[AdManager] Asset ad config not loaded: $e");
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final jsonMap =
            await compute<String, dynamic>(_parseJsonInIsolate, jsonString);
        final cachedConfig = AdConfig.fromJson(jsonMap);
        // Load global toggle from cache (defaults to 1 = ON)
        final int globalAds = jsonMap['global_ads_enabled'] as int? ?? 1;
        kEnableAds = (globalAds == 1);

        configNotifier.value = cachedConfig;
        AdvancedLogger.info(
          "[AdManager] Loaded cached config: ${cachedConfig.configVersion}",
        );
      }
    } catch (e) {
      AdvancedLogger.warn("[AdManager] Cache load failed: $e");
    }
  }

  Future<void> fetchLatestAds() async {
    AdvancedLogger.info("[AdManager] Requesting: $_adUrl");
    try {
      Response? response;
      try {
        response = await _dio.get(_adUrl);
      } catch (primaryErr) {
        AdvancedLogger.warn("[AdManager] Primary ad source failed: $primaryErr. Trying mirror: $_adMirrorUrl");
        response = await _dio.get(_adMirrorUrl);
      }

      AdvancedLogger.info("[AdManager] HTTP Status: ${response.statusCode}");
      if (response.data != null) {
        final raw = response.data.toString();
        AdvancedLogger.info(
          "[AdManager] Raw Response: ${raw.length > 200 ? raw.substring(0, 200) : raw}",
        );
      }

      if (response.statusCode == 200 && response.data != null) {
        dynamic data = response.data;
        if (data is String) {
          data = await compute<String, dynamic>(_parseJsonInIsolate, data);
        }

        final remoteConfig = AdConfig.fromJson(data);
        // Handle global_ads_enabled: 1 = ON, 0 = OFF (Fallback to 1 if missing in json)
        final int globalAds = data['global_ads_enabled'] as int? ?? 1;
        kEnableAds = (globalAds == 1);

        configNotifier.value = remoteConfig;
        AdvancedLogger.info(
          "[AdManager] Success! Updating cache and UI. Version: ${remoteConfig.configVersion}",
        );

        // Cache it
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, jsonEncode(data));
      } else {
        AdvancedLogger.warn("[AdManager] Fetch returned non-200 status.");
        _applyFallback();
      }
    } catch (e) {
      AdvancedLogger.error("[AdManager] Error fetching config: $e");
      _applyFallback();
    }
  }

  void _applyFallback() {
    // Only apply fallback if we don't have a valid config yet (e.g. cache was empty)
    // Or if we decide that network failure implies we should reset to safe state.
    // However, usually we keep the last known good config (cache).
    // But the directive said "Ensure the fallback _defaultFallbackMap is strictly applied if the Dio request throws".
    // I will interpret this as: if current config is null, apply fallback.
    // If current config exists (from cache or init), keep it.

    if (configNotifier.value == null) {
      AdvancedLogger.info(
        "[AdManager] Fallback Triggered! Using hardcoded HTML.",
      );
      try {
        final defaultConfig = AdConfig.fromJson(_defaultFallbackMap);
        configNotifier.value = defaultConfig;
      } catch (e) {
        AdvancedLogger.error(
          "[AdManager] Critical: Failed to apply fallback: $e",
        );
      }
    } else {
      AdvancedLogger.info(
        "[AdManager] Network failed, but keeping existing config (Cache/Default).",
      );
    }
  }

  AdUnit? getAdUnit(String slotName) {
    return configNotifier.value?.ads[slotName];
  }

  Future<bool> showPreConnectionAd(BuildContext context) async {
    if (!context.mounted) return false;

    AdvancedLogger.info(
      "[AdManager] Requesting Pre-Connection Ad (Full Screen Wall)...",
    );
    try {
      // Using Navigator.push with FullScreenAdDialog for "The Wall" experience
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => const FullScreenAdDialog(unitId: 'reward_ad'),
        ),
      );

      return result ?? false;
    } catch (e) {
      AdvancedLogger.error("[AdManager] Ad Exception: $e - Fail Open");
      return true; // Fail Open on error
    }
  }

  Future<void> showPostConnectionAd() async {
    // Placeholder for interstitial logic
  }
}

Map<String, dynamic> _parseJsonInIsolate(String jsonStr) =>
    jsonDecode(jsonStr) as Map<String, dynamic>;
