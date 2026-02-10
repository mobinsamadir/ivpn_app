import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:url_launcher/url_launcher.dart';

class AAdsBanner extends StatefulWidget {
  final double? width;
  final double? height;

  const AAdsBanner({
    super.key,
    this.width,
    this.height,
  });

  @override
  State<AAdsBanner> createState() => _AAdsBannerState();
}

class _AAdsBannerState extends State<AAdsBanner> {
  // Use adaptive sizing URL as per requirements
  static const String _adUrl = 'https://acceptable.a-ads.com/2426527/?size=Adaptive';
  static const String _adHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body { margin: 0; padding: 0; background-color: transparent; display: flex; justify-content: center; align-items: center; height: 100vh; overflow: hidden; }
</style>
</head>
<body>
  <div id="frame" style="width: 100%; position: relative; z-index: 99998; text-align: center;">
    <iframe data-aa='2426527' src='$_adUrl'
            style='border:0; padding:0; width:100%; height:100%; overflow:hidden; display: block; margin: auto'></iframe>
  </div>
</body>
</html>
''';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.transparent,
      child: Platform.isWindows ? const _WindowsWebView(htmlContent: _adHtml) : const _MobileWebView(htmlContent: _adHtml),
    );
  }
}

class _WindowsWebView extends StatefulWidget {
  final String htmlContent;
  const _WindowsWebView({required this.htmlContent});

  @override
  State<_WindowsWebView> createState() => _WindowsWebViewState();
}

class _WindowsWebViewState extends State<_WindowsWebView> {
  final _controller = WebviewController();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initWebview();
  }

  Future<void> _initWebview() async {
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.clearCache();
      await _controller.clearCookies();

      // Load content
      await _controller.loadStringContent(widget.htmlContent);

      // Handle navigation updates (if ad navigates self)
      _controller.url.listen((url) {
        if (url != 'about:blank' && !url.contains('data:text/html') && !url.contains('acceptable.a-ads.com')) {
             _launchUrl(url);
             // Reload to reset state if it navigated away
             _controller.loadStringContent(widget.htmlContent);
        }
      });

      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Windows WebView Error: $e');
    }
  }

  void _launchUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
       return const SizedBox();
    }
    return Webview(_controller);
  }
}

class _MobileWebView extends StatefulWidget {
  final String htmlContent;
  const _MobileWebView({required this.htmlContent});

  @override
  State<_MobileWebView> createState() => _MobileWebViewState();
}

class _MobileWebViewState extends State<_MobileWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            // Check if it's the initial load or the ad iframe source
            // The ad iframe src is 'https://acceptable.a-ads.com/...'
            // We allow that. Any click inside usually navigates to a different domain or path.
            final url = request.url;
            if (url.startsWith('data:') || url.contains('acceptable.a-ads.com')) {
              return NavigationDecision.navigate;
            }
            // Otherwise open in external browser
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(widget.htmlContent);
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
