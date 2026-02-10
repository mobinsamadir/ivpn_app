// lib/services/ad_manager_android.dart
import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../utils/advanced_logger.dart';
import 'ad_manager_interface.dart';

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
