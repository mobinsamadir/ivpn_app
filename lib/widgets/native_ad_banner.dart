import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ✅ اصلاح: ایمپورت‌های صحیح و کامل در ابتدای فایل
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';

Widget _createNativeAdWebView() {
  if (Platform.isWindows) {
    // Use webview_windows for Windows
    return const WindowsNativeAdView();
  } else {
    // Use webview_flutter for Android/iOS
    return const MobileNativeAdView();
  }
}

class NativeAdBanner extends StatefulWidget {
  const NativeAdBanner({super.key});

  @override
  State<NativeAdBanner> createState() => _NativeAdBannerState();
}

class _NativeAdBannerState extends State<NativeAdBanner> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      child: _createNativeAdWebView(),
    );
  }
}

// -----------------------------------------------------------
// Windows Implementation
// -----------------------------------------------------------
class WindowsNativeAdView extends StatefulWidget {
  const WindowsNativeAdView({super.key});

  @override
  State<WindowsNativeAdView> createState() => _WindowsNativeAdViewState();
}

class _WindowsNativeAdViewState extends State<WindowsNativeAdView> {
  late final WebviewController _controller;
  bool _webViewLoaded = false;
  bool _showFallback = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _controller = WebviewController();
    _initWebview();
  }

  Future<void> _initWebview() async {
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.transparent);

      String htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      margin: 0;
      padding: 0;
      height: 100%;
      background-color: transparent;
    }
  </style>
</head>
<body>
  <div id="frame" style="width: 100%; margin: auto; position: relative; z-index: 99998; display: flex; justify-content: center; height: 100%;">
     <iframe data-aa='2426527' src='https://ad.a-ads.com/2426527?size=300x250' style='border:0px; padding:0; width:300px; height:250px; overflow:hidden;'></iframe>
  </div>
</body>
</html>
''';

      // Set up timeout timer for fallback (5 seconds as requested)
      _timeoutTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && !_webViewLoaded) {
          setState(() {
            _showFallback = true;
          });
        }
      });

      await _controller.loadStringContent(htmlContent);

      // Listen for load completion
      _controller.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted && !_webViewLoaded && mounted) {
          setState(() {
            _webViewLoaded = true;
            _timeoutTimer?.cancel();
          });

          // Check if the content is actually loaded after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && !_webViewLoaded) {
              setState(() {
                _showFallback = true;
              });
            }
          });
        }
      });

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error initializing Native Ad WebView: $e');
      if (mounted) {
        setState(() {
          _showFallback = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showFallback) {
      return _buildFallback();
    }

    if (!_controller.value.isInitialized) {
      return Container(
        height: 120,
        color: const Color(0xFF1A1A1A),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          ),
        ),
      );
    }

    return Webview(_controller);
  }

  Widget _buildFallback() {
    return Container(
      height: 120,
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
          // Main clickable area
          InkWell(
            onTap: _openSmartLink,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.rocket_launch,
                    color: Colors.amber,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Premium Feature: Connect to Ultra-Fast Gaming Servers',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber, width: 1),
                    ),
                    child: const Text(
                      'TAP TO UNLOCK',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Close button
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _showFallback = true;
                  });
                },
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
    final Uri url = Uri.parse('https://ad.a-ads.com/2426527');
    if (await canLaunchUrl(url)) {
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Could not launch smartlink: $e');
      }
    } else {
      debugPrint('Could not launch smartlink: $url');
    }
  }
}

// -----------------------------------------------------------
// Mobile Implementation (Android/iOS)
// -----------------------------------------------------------
class MobileNativeAdView extends StatefulWidget {
  const MobileNativeAdView({super.key});

  @override
  State<MobileNativeAdView> createState() => _MobileNativeAdViewState();
}

class _MobileNativeAdViewState extends State<MobileNativeAdView> {
  late final WebViewController _controller;
  bool _webViewLoaded = false;
  bool _showFallback = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setBackgroundColor(Colors.transparent)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
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
             if (mounted) setState(() { _showFallback = true; });
          },
        ),
      );

    _initWebview();
  }

  Future<void> _initWebview() async {
    String htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      margin: 0;
      padding: 0;
      height: 100%;
      background-color: transparent;
    }
  </style>
</head>
<body>
  <div id="frame" style="width: 100%; margin: auto; position: relative; z-index: 99998; display: flex; justify-content: center; height: 100%;">
     <iframe data-aa='2426527' src='https://ad.a-ads.com/2426527?size=300x250' style='border:0px; padding:0; width:300px; height:250px; overflow:hidden;'></iframe>
  </div>
</body>
</html>
''';

    // Set up timeout timer for fallback (5 seconds as requested)
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_webViewLoaded) {
        setState(() {
          _showFallback = true;
        });
      }
    });

    try {
        await _controller.loadHtmlString(htmlContent);
    } catch (e) {
        debugPrint("Error loading HTML on mobile: $e");
        if(mounted) setState(() { _showFallback = true; });
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showFallback) {
      return _buildFallback();
    }
    // ویجت مخصوص موبایل
    return WebViewWidget(controller: _controller);
  }

  // کپی متد فال‌بک برای موبایل
  Widget _buildFallback() {
    return Container(
      height: 120,
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
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.rocket_launch, color: Colors.amber, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Premium Feature: Connect to Ultra-Fast Gaming Servers',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber, width: 1),
                    ),
                    child: const Text('TAP TO UNLOCK', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
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
    final Uri url = Uri.parse('https://ad.a-ads.com/2426527');
    if (await canLaunchUrl(url)) {
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Could not launch smartlink: $e');
      }
    }
  }
}