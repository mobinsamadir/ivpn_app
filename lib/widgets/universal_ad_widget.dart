import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

import '../services/ad_manager_service.dart';
import '../models/ad_config.dart';
import '../utils/advanced_logger.dart';

class UniversalAdWidget extends StatefulWidget {
  final String slot;
  final double? width;
  final double? height;

  const UniversalAdWidget({
    super.key,
    required this.slot,
    this.width,
    this.height,
  });

  @override
  State<UniversalAdWidget> createState() => _UniversalAdWidgetState();
}

class _UniversalAdWidgetState extends State<UniversalAdWidget> {
  AdUnit? _currentAd;

  @override
  void initState() {
    super.initState();
    // Initialize with current value
    _currentAd = AdManagerService().getAdUnit(widget.slot);

    // Listen for updates
    AdManagerService().configNotifier.addListener(_onConfigChanged);
  }

  @override
  void dispose() {
    AdManagerService().configNotifier.removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onConfigChanged() {
    final newAd = AdManagerService().getAdUnit(widget.slot);
    if (newAd != _currentAd) {
      if (mounted) {
        setState(() {
          _currentAd = newAd;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentAd == null || !_currentAd!.isEnabled) {
      return const SizedBox.shrink();
    }

    final ad = _currentAd!;
    // CRITICAL FIX: Fallback to a default height if null to prevent unconstrained expansion (Black Screen)
    final double effectiveHeight = widget.height ?? 250.0;

    return SizedBox(
      width: widget.width ?? double.infinity,
      height: effectiveHeight,
      child: _buildContent(ad),
    );
  }

  Widget _buildContent(AdUnit ad) {
    switch (ad.type) {
      case 'webview':
        return _WebViewAd(
          mediaSource: ad.mediaSource,
          targetUrl: ad.targetUrl,
        );
      case 'image':
        return _ImageAd(
          imageUrl: ad.mediaSource,
          targetUrl: ad.targetUrl,
        );
      case 'video':
        return _VideoAd(
          videoUrl: ad.mediaSource,
          targetUrl: ad.targetUrl,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// --- SUB-WIDGETS ---

class _ImageAd extends StatelessWidget {
  final String imageUrl;
  final String targetUrl;

  const _ImageAd({required this.imageUrl, required this.targetUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (targetUrl.isNotEmpty) {
          launchUrl(Uri.parse(targetUrl), mode: LaunchMode.externalApplication);
        }
      },
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      ),
    );
  }
}

class _VideoAd extends StatefulWidget {
  final String videoUrl;
  final String targetUrl;

  const _VideoAd({required this.videoUrl, required this.targetUrl});

  @override
  State<_VideoAd> createState() => _VideoAdState();
}

class _VideoAdState extends State<_VideoAd> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    await _videoController.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoController,
      autoPlay: true,
      looping: true,
      showControls: false, // Ad style
      aspectRatio: _videoController.value.aspectRatio,
    );

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_chewieController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onTap: () {
        if (widget.targetUrl.isNotEmpty) {
           launchUrl(Uri.parse(widget.targetUrl), mode: LaunchMode.externalApplication);
        }
      },
      child: Chewie(controller: _chewieController!),
    );
  }
}

class _WebViewAd extends StatelessWidget {
  final String mediaSource;
  final String targetUrl; // Not used for iframe usually, but maybe for overlay click

  const _WebViewAd({required this.mediaSource, required this.targetUrl});

  @override
  Widget build(BuildContext context) {
    String content = mediaSource;

    // Step 1: Detect Plain URL
    // If it starts with http/https and does NOT look like HTML tag, wrap it.
    if (content.startsWith('http') && !content.contains('<')) {
      content =
          '<iframe src="$content" style="border:0; width:100%; height:100%; overflow:hidden;" allow="autoplay"></iframe>';
    }

    // Step 2: Fix Protocol (Critical for A-Ads)
    if (content.contains("src='//")) {
      content = content.replaceAll("src='//", "src='https://");
    }

    // Step 3: Wrap in Full HTML Template (For Transparency & Centering)
    if (!content.contains("<html")) {
      content = """
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          html, body { margin: 0; padding: 0; width: 100%; height: 100%; background-color: transparent !important; }
          body { display: flex; justify-content: center; align-items: center; }
          iframe { border: none; width: 100%; height: 100%; overflow: hidden; display: block; }
        </style>
      </head>
      <body>
        $content
      </body>
      </html>
      """;
    }

    return Platform.isWindows
        ? _WindowsWebView(htmlContent: content)
        : _MobileWebView(htmlContent: content);
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

      AdvancedLogger.info('[AdWidget] Loading Windows HTML...');
      await _controller.loadStringContent(widget.htmlContent);

      _controller.url.listen((url) {
        if (url != 'about:blank' && !url.contains('data:text/html') && !url.contains('acceptable.a-ads.com')) {
             _launchUrl(url);
             _controller.loadStringContent(widget.htmlContent);
        }
      });

      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      AdvancedLogger.warn('Windows WebView Error: $e');
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
    try {
      if (_isInitialized) {
         _controller.stop();
      }
      _controller.dispose();
    } catch (e) {
      // Ignore
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      color: Colors.transparent,
      child: Webview(_controller),
    );
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AdvancedLogger.info('[AdWidget] Loading Mobile HTML...');
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            AdvancedLogger.info('[AdWidget] Mobile Page Loaded.');
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            if (url.startsWith('data:') || url.contains('acceptable.a-ads.com')) {
              return NavigationDecision.navigate;
            }
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(widget.htmlContent);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(
          controller: _controller,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{}, // Prevent scroll hijacking
        ),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
            ),
          ),
      ],
    );
  }
}
