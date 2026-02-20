import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ad_config.dart';
import '../utils/advanced_logger.dart';
// import '../widgets/full_screen_ad_dialog.dart'; // Disabled for Killswitch
// import 'windows_vpn_service.dart'; // Disabled for Killswitch

class AdManagerService {
  static final AdManagerService _instance = AdManagerService._internal();
  factory AdManagerService() => _instance;
  AdManagerService._internal();

  final ValueNotifier<AdConfig?> configNotifier = ValueNotifier<AdConfig?>(null);

  // Base64 Encoded Ad Config URL
  static final String _adUrl = utf8.decode(base64.decode('aHR0cHM6Ly9naXN0LmdpdGh1YnVzZXJjb250ZW50LmNvbS9tb2JpbnNhbWFkaXIvMDM3Y2RhYjhiODcxM2UxYzVhNTJkODE1NTM5ZjU2MzgvcmF3LzA4NjgzM2E5N2QyMzZkOWNmNTdkNDI3YzQ2YzIyNjg5MDQyNDRhN2UvYWRfY29uZmlnLmpzb24='));

  static const String _storageKey = "ad_config_cache";

  // Use the HTML from AAdsBanner as default
  static const String _defaultAdHtml = """
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    html, body { margin: 0; padding: 0; width: 100%; height: 100%; background-color: transparent !important; }
    body { display: flex; justify-content: center; align-items: center; }
    iframe { border: none; width: 100%; height: 100%; overflow: hidden; }
  </style>
</head>
<body>
  <iframe src="https://acceptable.a-ads.com/2426527/?size=Adaptive"></iframe>
</body>
</html>
""";

  // Construct the JSON structure
  static final Map<String, dynamic> _defaultFallbackMap = {
    "config_version": "fallback_v1",
    "ads": {
      "home_banner_top": {
        "isEnabled": true,
        "type": "webview",
        "mediaSource": _defaultAdHtml,
        "targetUrl": "",
        "timerSeconds": 0
      },
      "home_banner_bottom": {
        "isEnabled": true,
        "type": "webview",
        "mediaSource": _defaultAdHtml,
        "targetUrl": "",
        "timerSeconds": 0
      },
      "reward_ad": {
        "isEnabled": true,
        "type": "webview",
        "mediaSource": _defaultAdHtml,
        "targetUrl": "",
        "timerSeconds": 10 // Timer for reward ad
      }
    }
  };

  bool _initialized = false;
  final Dio _dio = Dio();

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

    // 2. Layer 2: Load from Cache
    await _loadFromCache();

    // 3. Layer 3: Network Fetch Removed from Startup
    // Only fetchLatestAds() will call network, triggered post-connect.

    // 4. Monitoring removed here. Managed by global ConfigManager hook.

    _initialized = true;
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final jsonMap = jsonDecode(jsonString);
        final cachedConfig = AdConfig.fromJson(jsonMap);
        configNotifier.value = cachedConfig;
        AdvancedLogger.info("[AdManager] Loaded cached config: ${cachedConfig.configVersion}");
      }
    } catch (e) {
      AdvancedLogger.warn("[AdManager] Cache load failed: $e");
    }
  }

  Future<void> fetchLatestAds() async {
    AdvancedLogger.info("[AdManager] Requesting: $_adUrl");
    try {
      final response = await _dio.get(_adUrl);

      AdvancedLogger.info("[AdManager] HTTP Status: ${response.statusCode}");
      if (response.data != null) {
        final raw = response.data.toString();
        AdvancedLogger.info("[AdManager] Raw Response: ${raw.length > 200 ? raw.substring(0, 200) : raw}");
      }

      if (response.statusCode == 200 && response.data != null) {
        dynamic data = response.data;
        if (data is String) {
           data = jsonDecode(data);
        }

        final remoteConfig = AdConfig.fromJson(data);
        configNotifier.value = remoteConfig;
        AdvancedLogger.info("[AdManager] Success! Updating cache and UI. Version: ${remoteConfig.configVersion}");

        // Cache it
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, jsonEncode(data));
      } else {
        AdvancedLogger.warn("[AdManager] Fetch returned non-200 status.");
        AdvancedLogger.info("[AdManager] Fallback Triggered! Using hardcoded HTML.");
      }
    } catch (e) {
      AdvancedLogger.error("[AdManager] Error fetching config: $e");
      AdvancedLogger.info("[AdManager] Fallback Triggered! Using hardcoded HTML.");
    }
  }

  AdUnit? getAdUnit(String slotName) {
    return configNotifier.value?.ads[slotName];
  }

  Future<bool> showPreConnectionAd(BuildContext context) async {
    // KILLSWITCH ENGAGED: Bypassing Ad for debugging
    AdvancedLogger.warn("[AdManager] KILLSWITCH: Bypassing Pre-Connection Ad.");
    return true;

    /*
    if (!context.mounted) return false;

    AdvancedLogger.info("[AdManager] Requesting Pre-Connection Ad (Full Screen Wall)...");
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
    */
  }

  Future<void> showPostConnectionAd() async {
     // Placeholder for interstitial logic
  }
}
