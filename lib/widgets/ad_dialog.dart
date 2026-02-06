import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

class AdDialog extends StatefulWidget {
  final String adUrl;
  
  const AdDialog({
    super.key,
    required this.adUrl,
  });

  @override
  State<AdDialog> createState() => _AdDialogState();
}

class _AdDialogState extends State<AdDialog> {
  final _controller = WebviewController();
  bool _isCloseVisible = false;
  bool _isLoading = true;
  Timer? _closeButtonTimer;

  @override
  void initState() {
    super.initState();
    _initWebview();
    
    // Show close button after 5 seconds
    _closeButtonTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isCloseVisible = true;
        });
      }
    });
  }

  Future<void> _initWebview() async {
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(const Color(0xFF1E1E1E));
      await _controller.loadUrl(widget.adUrl);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error initializing ad WebView: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _closeButtonTimer?.cancel();
    _controller.dispose();
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
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // WebView Content
            if (_isLoading)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.blueAccent),
                    SizedBox(height: 16),
                    Text(
                      'Loading advertisement...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Webview(_controller),
              ),
            
            // Close Button (appears after 5 seconds)
            Positioned(
              top: 0,
              right: 0,
              child: Visibility(
                visible: _isCloseVisible,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ),
              ),
            ),
            
            // Timer indicator (shows countdown until close button appears)
            if (!_isCloseVisible)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Please wait...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
