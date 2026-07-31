import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

import '../services/ad_manager_service.dart';
import '../models/ad_config.dart';
import '../utils/advanced_logger.dart';
import '../widgets/scale_on_tap.dart';

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
  late final ValueNotifier<AdUnit?> _currentAdNotifier;

  @override
  void initState() {
    super.initState();
    _currentAdNotifier = ValueNotifier<AdUnit?>(AdManagerService().getAdUnit(widget.slot));
    AdManagerService().configNotifier.addListener(_onConfigChanged);
  }

  @override
  void dispose() {
    AdManagerService().configNotifier.removeListener(_onConfigChanged);
    _currentAdNotifier.dispose();
    super.dispose();
  }

  void _onConfigChanged() {
    final newAd = AdManagerService().getAdUnit(widget.slot);
    if (newAd != _currentAdNotifier.value) {
      if (mounted) {
        _currentAdNotifier.value = newAd;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdUnit?>(
      valueListenable: _currentAdNotifier,
      builder: (context, currentAd, child) {
        if (!kEnableAds) {
          return const SizedBox.shrink();
        }

        if (currentAd == null || !currentAd.isEnabled) {
          return const SizedBox.shrink();
        }

        final ad = currentAd;
        double effectiveHeight = widget.height ?? 250.0;

        if (widget.slot == 'home_banner_top' ||
            widget.slot == 'home_banner_bottom') {
          effectiveHeight = 60.0;
        }

        return SizedBox(
          width: widget.width ?? double.infinity,
          height: effectiveHeight,
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(height: effectiveHeight),
            child: _buildContent(ad),
          ),
        );
      },
    );
  }

  Widget _buildContent(AdUnit ad) {
    switch (ad.type) {
      case 'webview':
        return _WebViewAd(mediaSource: ad.mediaSource, targetUrl: ad.targetUrl);
      case 'image':
        return _ImageAd(imageUrl: ad.mediaSource, targetUrl: ad.targetUrl);
      case 'video':
        return _VideoAd(videoUrl: ad.mediaSource, targetUrl: ad.targetUrl);
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
    return ScaleOnTap(
      onTap: () {
        if (targetUrl.isNotEmpty) {
          launchUrl(Uri.parse(targetUrl), mode: LaunchMode.externalApplication);
        }
      },
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        placeholder: (context, url) =>
            const Center(child: CircularProgressIndicator()),
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
  final ValueNotifier<ChewieController?> _chewieControllerNotifier = ValueNotifier<ChewieController?>(null);

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    await _videoController.initialize();

    if (mounted) {
      _chewieControllerNotifier.value = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: true,
        looping: true,
        showControls: false, // Ad style
        aspectRatio: _videoController.value.aspectRatio,
      );
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieControllerNotifier.value?.dispose();
    _chewieControllerNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChewieController?>(
      valueListenable: _chewieControllerNotifier,
      builder: (context, chewieController, child) {
        if (chewieController == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return ScaleOnTap(
          onTap: () {
            if (widget.targetUrl.isNotEmpty) {
              launchUrl(
                Uri.parse(widget.targetUrl),
                mode: LaunchMode.externalApplication,
              );
            }
          },
          child: Chewie(controller: chewieController),
        );
      },
    );
  }
}

class _WebViewAd extends StatelessWidget {
  final String mediaSource;
  final String
      targetUrl; // Not used for iframe usually, but maybe for overlay click

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

    return _MobileWebView(htmlContent: content);
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
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    AdvancedLogger.info('[AdWidget] Loading Mobile HTML...');
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..enableZoom(false)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            AdvancedLogger.info('[AdWidget] Mobile Page Loaded.');
            if (mounted) {
              _isLoadingNotifier.value = false;
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            if (url.startsWith('data:') ||
                url.contains('acceptable.a-ads.com')) {
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
  void dispose() {
    _isLoadingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(
          controller: _controller,
          gestureRecognizers: <Factory<
              OneSequenceGestureRecognizer>>{}, // Prevent scroll hijacking
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _isLoadingNotifier,
          builder: (context, isLoading, child) {
            if (isLoading) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
