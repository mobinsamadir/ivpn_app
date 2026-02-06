import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;

// ✅ اصلاح مهم: ایمپورت‌ها به بالا منتقل شدند و هر دو پکیج فراخوانی می‌شوند
// تا کامپایلر بتواند کدهای هر دو کلاس ویندوز و موبایل را تشخیص دهد.
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../services/config_manager.dart';
import '../utils/advanced_logger.dart';

class AdBannerWebView extends StatefulWidget {
  const AdBannerWebView({super.key});

  @override
  State<AdBannerWebView> createState() => _AdBannerWebViewState();
}

class _AdBannerWebViewState extends State<AdBannerWebView> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ConfigManager>(
      builder: (context, configManager, child) {
        return Container(
          height: 80,
          // Pass the live connection status to the child widgets
          child: Platform.isWindows
              ? WindowsWebViewAd(isConnected: configManager.isConnected)
              : MobileWebViewAd(isConnected: configManager.isConnected),
        );
      },
    );
  }
}

// -----------------------------------------------------------
// Windows Implementation
// -----------------------------------------------------------
class WindowsWebViewAd extends StatefulWidget {
  final bool isConnected;

  const WindowsWebViewAd({super.key, required this.isConnected});

  @override
  State<WindowsWebViewAd> createState() => _WindowsWebViewAdState();
}

class _WindowsWebViewAdState extends State<WindowsWebViewAd> {
  late final WebviewController _controller; // مربوط به پکیج ویندوز
  bool _webViewLoaded = false;
  bool _showFallback = false;
  Timer? _timeoutTimer;
  late bool _isConnected;

  @override
  void initState() {
    super.initState();
    _isConnected = widget.isConnected;
    _controller = WebviewController();
    _initWebview();
  }

  @override
  void didUpdateWidget(WindowsWebViewAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isConnected != widget.isConnected) {
      _isConnected = widget.isConnected;
      _reloadWebView();
    }
  }

  Future<void> _reloadWebView() async {
    if (mounted) {
      setState(() {
        _webViewLoaded = false;
        _showFallback = false;
      });

      String htmlContent = _isConnected
          ? await _getConnectedAdContent()
          : await _getDisconnectedAdContent();

      try {
        // Load a neutral URL first to establish a valid origin, then inject content
        await _controller.loadUrl('https://www.example.com');
        // Wait a moment for the page to load, then inject the content
        await Future.delayed(const Duration(milliseconds: 500));
        await _injectHtmlContent(htmlContent);
      } catch (e) {
        debugPrint('Error reloading Windows WebView: $e');
        if (mounted) setState(() { _showFallback = true; });
      }
    }
  }

  Future<void> _initWebview() async {
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.transparent);
      
      // FIX: Clear cache and Spoof UA to bypass ad blockers
      await _controller.clearCache();
      await _controller.clearCookies();
      await _controller.setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");

      String htmlContent = _isConnected
          ? await _getConnectedAdContent()
          : await _getDisconnectedAdContent();

      _timeoutTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && !_webViewLoaded) {
          setState(() {
            _showFallback = true;
          });
        }
      });

      // Load a neutral URL first to establish a valid origin, then inject content
      await _controller.loadUrl('https://www.example.com');
      // Wait a moment for the page to load, then inject the content
      await Future.delayed(const Duration(milliseconds: 500));
      await _injectHtmlContent(htmlContent);

      _controller.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted && !_webViewLoaded && mounted) {
          setState(() {
            _webViewLoaded = true;
            _timeoutTimer?.cancel();
          });

          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && !_webViewLoaded) {
              setState(() { _showFallback = true; });
            }
          });
        }
      });

      // Note: WebviewController in webview_windows might not support webResourceError
      // check if it exists before using or skip for Windows as per instructions
      // Removed onError listener as it's not supported in webview_windows

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error initializing Windows WebView: $e');
      if (mounted) setState(() { _showFallback = true; });
    }
  }

  // Load fallback content when remote ad fails
  // Helper method to inject HTML content via JavaScript
  Future<void> _injectHtmlContent(String htmlContent) async {
    try {
      // Escape the HTML content to be safe inside a JS string
      final escapedContent = htmlContent.replaceAll(r"'", r"\'").replaceAll('\n', r'\n').replaceAll('\r', r'\r');
      await _controller.executeScript(
        "document.body.innerHTML = '$escapedContent'; document.body.style.backgroundColor = 'transparent';"
      );
    } catch (e) {
      debugPrint('Error injecting HTML content: $e');
    }
  }

  Future<void> _loadFallbackContent() async {
    if (mounted) {
      setState(() {
        _showFallback = true;
      });

      // Also try to load the local placeholder content directly
      String fallbackContent = await _getDisconnectedAdContent();
      try {
        // Load a neutral URL first to establish a valid origin, then inject content
        await _controller.loadUrl('https://www.example.com');
        // Wait a moment for the page to load, then inject the content
        await Future.delayed(const Duration(milliseconds: 500));
        await _injectHtmlContent(fallbackContent);
      } catch (e) {
        debugPrint('Error loading fallback content: $e');
      }
    }
  }

  Future<String> _getConnectedAdContent() async {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    html, body { height: 50px; margin: 0; padding: 0; overflow: hidden; background-color: transparent; display: flex; justify-content: center; align-items: center; }
  </style>
</head>
<body>
  <div id="frame" style="width: 100%; margin: auto; position: relative; z-index: 99998; display: flex; justify-content: center;">
     <iframe data-aa='2426527' src='https://ad.a-ads.com/2426527?size=320x50' style='border:0px; padding:0; width:320px; height:50px; overflow:hidden;'></iframe>
  </div>
</body>
</html>
''';
  }

  Future<String> _getDisconnectedAdContent() async {
    // Load the placeholder HTML file
    String assetPath = 'assets/html/placeholder_ad.html';
    String content = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Connect to See Ads</title>
  <style>
    body {
      margin: 0;
      padding: 0;
      display: flex;
      justify-content: center;
      align-items: center;
      background-color: transparent;
      overflow: hidden;
      height: 100%;
      width: 100%;
      font-family: Arial, sans-serif;
      color: white;
      text-align: center;
    }
    .ad-container {
      width: 100%;
      height: 100%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background: linear-gradient(135deg, #1e3c72, #2a5298);
      padding: 10px;
      box-sizing: border-box;
    }
    .title {
      font-size: 14px;
      font-weight: bold;
      margin-bottom: 8px;
    }
    .subtitle {
      font-size: 12px;
      opacity: 0.8;
    }
  </style>
</head>
<body>
  <div class="ad-container">
    <div class="title">🔒 VPN Connected</div>
    <div class="subtitle">Ads are blocked<br>when VPN is active</div>
  </div>
</body>
</html>
''';
    return content;
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showFallback) return _buildFallback();

    if (!_controller.value.isInitialized) {
      return Container(
        height: 80,
        color: const Color(0xFF1A1A1A),
        child: const Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)),
          ),
        ),
      );
    }

    return Webview(_controller);
  }

  Widget _buildFallback() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          colors: [Colors.blueGrey, Color(0xFF000000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: _openSmartLink,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: const Row(
                children: [
                  Icon(Icons.rocket_launch, color: Colors.amber, size: 24),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'BOOST CONNECTION: Tap to unlock Premium Low-Ping Servers',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Icon(Icons.rocket_launch, color: Colors.amber, size: 24),
                ],
              ),
            ),
          ),
          Positioned(
            top: 4, right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                onPressed: () => setState(() { _showFallback = true; }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getEffectiveGateAdContent() async {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { margin: 0; padding: 0; height: 100%; background-color: transparent; }
  </style>
</head>
<body>
  <div id="frame" style="width: 100%; margin: auto; position: relative; z-index: 99998; display: flex; justify-content: center; height: 100%;">
     <iframe data-aa='2426527' src='https://ad.a-ads.com/2426527?size=Adaptive' style='border:0px; padding:0; width:100%; height:100%; overflow:hidden;'></iframe>
  </div>
</body>
</html>
''';
  }

  void _openSmartLink() async {
    // Load the A-Ads ad content in the WebView instead of opening external URL
    String adContent = await _getEffectiveGateAdContent();

    try {
      // Load a neutral URL first to establish a valid origin, then inject content
      await _controller.loadUrl('https://www.example.com');
      // Wait a moment for the page to load, then inject the content
      await Future.delayed(const Duration(milliseconds: 500));
      await _injectHtmlContent(adContent);
      setState(() {
        _showFallback = false;
        _webViewLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading A-Ads ad content on Windows: $e');
    }
  }
}

// -----------------------------------------------------------
// Mobile Implementation (Android/iOS)
// -----------------------------------------------------------
class MobileWebViewAd extends StatefulWidget {
  final bool isConnected;

  const MobileWebViewAd({super.key, required this.isConnected});

  @override
  State<MobileWebViewAd> createState() => _MobileWebViewAdState();
}

class _MobileWebViewAdState extends State<MobileWebViewAd> {
  late final WebViewController _controller; // مربوط به پکج فلاتر (موبایل)
  bool _webViewLoaded = false;
  bool _showFallback = false;
  Timer? _timeoutTimer;
  late bool _isConnected;

  @override
  void initState() {
    super.initState();
    _isConnected = widget.isConnected;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent);

    // Platform-specific navigation delegate setup
    if (!Platform.isWindows) {
      _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _webViewLoaded = true;
                _timeoutTimer?.cancel();
              });
            }
          },
          onWebResourceError: (error) {
             debugPrint('Ad Load Error: ${error.description}');
             // Load fallback content when remote ad fails
             _loadFallbackContent();
             // اگر خطای لود داشتیم فال‌بک را نشان بده
             if (mounted) setState(() { _showFallback = true; });
          },
        ),
      );
    } else {
      _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _webViewLoaded = true;
                _timeoutTimer?.cancel();
              });
            }
          },
        ),
      );
    }

    _initWebview();
  }

  @override
  void didUpdateWidget(MobileWebViewAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isConnected != widget.isConnected) {
      _isConnected = widget.isConnected;
      _reloadWebView();
    }
  }

  Future<void> _reloadWebView() async {
    if (mounted) {
      setState(() {
        _webViewLoaded = false;
        _showFallback = false;
      });
      
      String htmlContent = _isConnected 
          ? await _getConnectedAdContent() 
          : await _getDisconnectedAdContent();
          
      try {
        await _controller.loadHtmlString(htmlContent);
      } catch (e) {
        debugPrint("Error reloading HTML on mobile: $e");
        if(mounted) setState(() { _showFallback = true; });
      }
    }
  }

  Future<void> _initWebview() async {
    String htmlContent = _isConnected
        ? await _getConnectedAdContent()
        : await _getDisconnectedAdContent();

    _timeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_webViewLoaded) {
        setState(() { _showFallback = true; });
      }
    });

    try {
        await _controller.loadHtmlString(htmlContent);
    } catch (e) {
        debugPrint("Error loading HTML on mobile: $e");
        if(mounted) setState(() { _showFallback = true; });
    }
  }

  Future<String> _getConnectedAdContent() async {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    html, body { height: 50px; margin: 0; padding: 0; overflow: hidden; background-color: transparent; display: flex; justify-content: center; align-items: center; }
  </style>
</head>
<body>
  <div id="frame" style="width: 100%; margin: auto; position: relative; z-index: 99998; display: flex; justify-content: center;">
     <iframe data-aa='2426527' src='https://ad.a-ads.com/2426527?size=320x50' style='border:0px; padding:0; width:320px; height:50px; overflow:hidden;'></iframe>
  </div>
</body>
</html>
''';
  }

  Future<String> _getDisconnectedAdContent() async {
    // Load the placeholder HTML file
    String content = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Connect to See Ads</title>
  <style>
    body {
      margin: 0;
      padding: 0;
      display: flex;
      justify-content: center;
      align-items: center;
      background-color: transparent;
      overflow: hidden;
      height: 100%;
      width: 100%;
      font-family: Arial, sans-serif;
      color: white;
      text-align: center;
    }
    .ad-container {
      width: 100%;
      height: 100%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background: linear-gradient(135deg, #1e3c72, #2a5298);
      padding: 10px;
      box-sizing: border-box;
    }
    .title {
      font-size: 14px;
      font-weight: bold;
      margin-bottom: 8px;
    }
    .subtitle {
      font-size: 12px;
      opacity: 0.8;
    }
  </style>
</head>
<body>
  <div class="ad-container">
    <div class="title">🔒 VPN Connected</div>
    <div class="subtitle">Ads are blocked<br>when VPN is active</div>
  </div>
</body>
</html>
''';
    return content;
  }

  // Load fallback content when remote ad fails
  Future<void> _loadFallbackContent() async {
    if (mounted) {
      setState(() {
        _showFallback = true;
      });

      // Also try to load the local placeholder content directly
      String fallbackContent = await _getDisconnectedAdContent();
      try {
        await _controller.loadHtmlString(fallbackContent);
      } catch (e) {
        debugPrint('Error loading fallback content: $e');
      }
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<String> _getEffectiveGateAdContent() async {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { margin: 0; padding: 0; height: 100%; background-color: transparent; }
  </style>
</head>
<body>
  <div id="frame" style="width: 100%; margin: auto; position: relative; z-index: 99998; display: flex; justify-content: center; height: 100%;">
     <iframe data-aa='2426527' src='https://ad.a-ads.com/2426527?size=Adaptive' style='border:0px; padding:0; width:100%; height:100%; overflow:hidden;'></iframe>
  </div>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    if (_showFallback) {
      return _buildFallback();
    }
    // ویجت مخصوص موبایل
    return WebViewWidget(controller: _controller);
  }

  // کپی همان فال‌بک بالا برای موبایل
  Widget _buildFallback() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          colors: [Colors.blueGrey, Color(0xFF000000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: _openSmartLink,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: const Row(
                children: [
                  Icon(Icons.rocket_launch, color: Colors.amber, size: 24),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'BOOST CONNECTION: Tap to unlock Premium Low-Ping Servers',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Icon(Icons.rocket_launch, color: Colors.amber, size: 24),
                ],
              ),
            ),
          ),
           Positioned(
            top: 4, right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                onPressed: () => setState(() { _showFallback = true; }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSmartLink() async {
    // Load the A-Ads ad content in the WebView instead of opening external URL
    String adContent = await _getEffectiveGateAdContent();

    try {
      await _controller.loadHtmlString(adContent);
      setState(() {
        _showFallback = false;
        _webViewLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading A-Ads ad content on Mobile: $e');
    }
  }
}