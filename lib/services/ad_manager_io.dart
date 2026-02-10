import 'dart:io';
import 'ad_manager_interface.dart';
import 'ad_manager_android.dart';
import 'ad_manager_windows.dart';

AdManager getPlatformAdManager() {
  if (Platform.isAndroid || Platform.isIOS) {
    return AndroidAdManager();
  } else if (Platform.isWindows) {
    return WindowsAdManager();
  }
  return MockAdManager();
}

class MockAdManager implements AdManager {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> showInterstitial() async => true;

  @override
  Future<bool> showRewarded() async => true;
}
