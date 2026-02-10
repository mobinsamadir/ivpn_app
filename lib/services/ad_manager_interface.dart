// lib/services/ad_manager_interface.dart
abstract class AdManager {
  Future<void> initialize();
  Future<bool> showInterstitial();
  Future<bool> showRewarded();
}
