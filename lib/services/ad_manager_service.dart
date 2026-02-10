import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:webview_windows/webview_windows.dart';
import '../utils/advanced_logger.dart';

// Abstract Interface
abstract class AdManager {
  Future<void> initialize();
  Future<bool> showInterstitial();
  Future<bool> showRewarded();
}

class AdManagerService {
  static final AdManagerService _instance = AdManagerService._internal();
  factory AdManagerService() => _instance;
  AdManagerService._internal();

  late AdManager _manager;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    AdvancedLogger.info("[AdManager] Initializing...");

    if (kIsWeb) {
      _manager = MockAdManager();
    } else if (Platform.isAndroid || Platform.isIOS) {
      _manager = AndroidAdManager();
    } else if (Platform.isWindows) {
      _manager = WindowsAdManager();
    } else {
      _manager = MockAdManager();
    }

    await _manager.initialize();
    _initialized = true;
  }

  /// Shows a Rewarded Ad (Pre-Connection).
  /// Returns `true` if ad completed OR failed (Fail-Open).
  /// Returns `false` only if user cancelled/closed prematurely (if applicable).
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

// --- Android Implementation ---
class AndroidAdManager implements AdManager {
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;

  // Test IDs
  final String _interstitialId = 'ca-app-pub-3940256099942544/1033173712';
  final String _rewardedId = 'ca-app-pub-3940256099942544/5224354917';

  @override
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
  }

  void _loadInterstitial() {
    InterstitialAd.load(
        adUnitId: _interstitialId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (Ad ad) {
            _interstitialAd = ad as InterstitialAd;
          },
          onAdFailedToLoad: (LoadAdError error) {
            AdvancedLogger.warn('[AdManager] Interstitial failed to load: $error');
            _interstitialAd = null;
          },
        ));
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: _rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (Ad ad) {
          _rewardedAd = ad as RewardedAd;
        },
        onAdFailedToLoad: (LoadAdError error) {
          AdvancedLogger.warn('[AdManager] Rewarded failed to load: $error');
          _rewardedAd = null;
        },
      ),
    );
  }

  @override
  Future<bool> showInterstitial() async {
    if (_interstitialAd == null) {
      _loadInterstitial(); // Try reloading for next time
      return true; // Fail open
    }

    final completer = Completer<bool>();

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (Ad ad) {
        ad.dispose();
        _loadInterstitial();
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
        ad.dispose();
        _loadInterstitial();
        if (!completer.isCompleted) completer.complete(true);
      },
    );

    _interstitialAd!.show();
    return completer.future;
  }

  @override
  Future<bool> showRewarded() async {
    if (_rewardedAd == null) {
      _loadRewarded();
      return true; // Fail open
    }

    final completer = Completer<bool>();
    bool rewardEarned = false;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (Ad ad) {
        ad.dispose();
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(rewardEarned);
      },
      onAdFailedToShowFullScreenContent: (Ad ad, AdError error) {
        ad.dispose();
        _loadRewarded();
        if (!completer.isCompleted) completer.complete(true); // Fail open
      },
    );

    _rewardedAd!.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
      rewardEarned = true;
    });

    return completer.future;
  }
}

// --- Windows Implementation (Mock/Webview) ---
class WindowsAdManager implements AdManager {
  final _controller = WebviewController();
  bool _isWebviewReady = false;

  @override
  Future<void> initialize() async {
    try {
      await _controller.initialize();
      _isWebviewReady = true;
      // Preload dummy ad
      // await _controller.loadUrl('https://google.com'); // Placeholder
    } catch (e) {
      AdvancedLogger.warn('[AdManager] Windows Webview Init Failed: $e');
    }
  }

  @override
  Future<bool> showInterstitial() async {
    if (!_isWebviewReady) return true;
    AdvancedLogger.info("[AdManager] Showing Windows Interstitial (Mock)");
    // Real impl: Show Dialog with Webview widget
    return true;
  }

  @override
  Future<bool> showRewarded() async {
    if (!_isWebviewReady) return true;
    AdvancedLogger.info("[AdManager] Showing Windows Rewarded (Mock)");
    // Real impl: Show Dialog, wait for JS callback
    return true;
  }
}

class MockAdManager implements AdManager {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> showInterstitial() async => true;

  @override
  Future<bool> showRewarded() async => true;
}
