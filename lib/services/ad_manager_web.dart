import 'ad_manager_interface.dart';

AdManager getPlatformAdManager() => MockAdManager();

class MockAdManager implements AdManager {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> showInterstitial() async => true;

  @override
  Future<bool> showRewarded() async => true;
}
