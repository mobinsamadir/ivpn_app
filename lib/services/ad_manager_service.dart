import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/advanced_logger.dart';
import 'ad_manager_interface.dart';

// Conditionally import the correct implementation
import 'ad_manager_stub.dart'
  if (dart.library.io) 'ad_manager_io.dart'
  if (dart.library.html) 'ad_manager_web.dart'; // Web not used but good practice

class AdManagerService {
  static final AdManagerService _instance = AdManagerService._internal();
  factory AdManagerService() => _instance;
  AdManagerService._internal();

  late AdManager _manager;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    AdvancedLogger.info("[AdManager] Initializing...");

    // Use factory to get platform implementation
    _manager = getPlatformAdManager();

    await _manager.initialize();
    _initialized = true;
  }

  /// Shows a Rewarded Ad (Pre-Connection).
  /// Returns `true` if ad completed OR failed (Fail-Open).
  Future<bool> showPreConnectionAd() async {
     if (!_initialized) await initialize();

     AdvancedLogger.info("[AdManager] Requesting Pre-Connection Ad...");
     try {
       // Timeout ensures we never block the user for more than 5s
       return await _manager.showRewarded().timeout(const Duration(seconds: 5), onTimeout: () {
         AdvancedLogger.warn("[AdManager] Ad Timeout (5s) - Triggering Fail-Open");
         return true; // Proceed
       });
     } catch (e) {
       AdvancedLogger.error("[AdManager] Ad Exception: $e - Triggering Fail-Open");
       return true; // Fail Open
     }
  }

  /// Shows an Interstitial Ad (Post-Connection).
  /// Does not block connection, fire and forget.
  Future<void> showPostConnectionAd() async {
     if (!_initialized) return;
     try {
       _manager.showInterstitial();
     } catch (e) {
       AdvancedLogger.error("[AdManager] Post-Connection Ad Failed: $e");
     }
  }
}
