// lib/services/ad_manager_windows.dart
import 'dart:async';
import 'package:webview_windows/webview_windows.dart';
import '../utils/advanced_logger.dart';
import 'ad_manager_interface.dart';

class WindowsAdManager implements AdManager {
  final _controller = WebviewController();
  bool _isWebviewReady = false;

  @override
  Future<void> initialize() async {
    try {
      await _controller.initialize();
      _isWebviewReady = true;
    } catch (e) {
      AdvancedLogger.warn('[AdManager] Windows Webview Init Failed: $e');
    }
  }

  @override
  Future<bool> showInterstitial() async {
    if (!_isWebviewReady) return true;
    AdvancedLogger.info("[AdManager] Showing Windows Interstitial (Mock)");
    return true;
  }

  @override
  Future<bool> showRewarded() async {
    if (!_isWebviewReady) return true;
    AdvancedLogger.info("[AdManager] Showing Windows Rewarded (Mock)");
    return true;
  }
}
