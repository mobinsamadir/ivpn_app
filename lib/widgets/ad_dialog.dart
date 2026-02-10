import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';

class AdDialog extends StatefulWidget {
  final String unitId;

  const AdDialog({
    super.key,
    this.unitId = '2426527', // Default A-Ads Unit ID
  });

  @override
  State<AdDialog> createState() => _AdDialogState();
}

class _AdDialogState extends State<AdDialog> {
  int _timeLeft = 10;
  bool _canClose = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        if (mounted) {
          setState(() {
            _timeLeft--;
          });
        }
      } else {
        _timer?.cancel();
        if (mounted) {
          setState(() {
            _canClose = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sponsored Content',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_canClose)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            
            // WebView Content
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.black,
                  child: _buildWebView(),
                ),
              ),
            ),
            
            const SizedBox(height: 16),

            // Footer Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _canClose
                    ? () => Navigator.of(context).pop(true)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canClose ? Colors.green : Colors.grey[800],
                  disabledBackgroundColor: Colors.grey[800],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _canClose ? 'Close & Connect' : 'Please wait (${_timeLeft}s)...',
                  style: TextStyle(
                    color: _canClose ? Colors.white : Colors.white54,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    final htmlContent = _getHtmlContent(widget.unitId);
    if (Platform.isWindows) {
      return WindowsAdWebView(htmlContent: htmlContent);
    } else {
      return MobileAdWebView(htmlContent: htmlContent);
    }
  }

  String _getHtmlContent(String unitId) {
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body { margin: 0; padding: 0; background-color: #000000; display: flex; justify-content: center; align-items: center; height: 100vh; color: white; }
</style>
</head>
<body>
  <div style="width: 100%; height: 100%; display: flex; justify-content: center; align-items: center;">
    <iframe data-aa='$unitId' src='https://ad.a-ads.com/$unitId?size=Adaptive' style='border:0px; padding:0; width:100%; height:100%; overflow:hidden;'></iframe>
  </div>
</body>
</html>
''';
  }
}

// Windows Implementation
class WindowsAdWebView extends StatefulWidget {
  final String htmlContent;
  const WindowsAdWebView({super.key, required this.htmlContent});

  @override
  State<WindowsAdWebView> createState() => _WindowsAdWebViewState();
}

class _WindowsAdWebViewState extends State<WindowsAdWebView> {
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
      await _controller.loadStringContent(widget.htmlContent);
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Windows WebView Error: $e');
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
      return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
    }
    return Webview(_controller);
  }
}

// Mobile Implementation
class MobileAdWebView extends StatefulWidget {
  final String htmlContent;
  const MobileAdWebView({super.key, required this.htmlContent});

  @override
  State<MobileAdWebView> createState() => _MobileAdWebViewState();
}

class _MobileAdWebViewState extends State<MobileAdWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
             debugPrint('Mobile WebView Error: ${error.description}');
          }
        ),
      )
      ..loadHtmlString(widget.htmlContent);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
      ],
    );
  }
}
