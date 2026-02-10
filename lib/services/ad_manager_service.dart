import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/advanced_logger.dart';
import '../widgets/ad_dialog.dart';
import 'ad_manager_interface.dart';

// Conditionally import the correct implementation
import 'ad_manager_stub.dart'
  if (dart.library.io) 'ad_manager_io.dart'
  if (dart.library.html) 'ad_manager_web.dart';

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

  /// Shows a Rewarded Ad (Pre-Connection) using a Dialog.
  /// Returns `true` if ad was closed successfully (Close & Connect).
  Future<bool> showPreConnectionAd(BuildContext context) async {
     if (!_initialized) await initialize();
     if (!context.mounted) return false;

     AdvancedLogger.info("[AdManager] Requesting Pre-Connection Ad (Dialog)...");
     try {
       final result = await showDialog<bool>(
         context: context,
         barrierDismissible: false,
         builder: (context) => const AdDialog(unitId: '2426527'),
       );

       return result ?? false;
     } catch (e) {
       AdvancedLogger.error("[AdManager] Ad Dialog Exception: $e - Fail Open");
       return true; // Fail Open on error
     }
  }

  /// Shows an Interstitial Ad (Post-Connection).
  /// Currently uses the mock manager or placeholder.
  Future<void> showPostConnectionAd() async {
     if (!_initialized) return;
     try {
       _manager.showInterstitial();
     } catch (e) {
       AdvancedLogger.error("[AdManager] Post-Connection Ad Failed: $e");
     }
  }
}
