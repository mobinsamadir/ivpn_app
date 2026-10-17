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
    // Initialize with current value
    _currentAdNotifier =
        ValueNotifier<AdUnit?>(AdManagerService().getAdUnit(widget.slot));

    // Listen for updates
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
    if (!kEnableAds) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<AdUnit?>(
      valueListenable: _currentAdNotifier,
      builder: (context, currentAd, child) {
        if (currentAd == null || !currentAd.isEnabled) {
          return const SizedBox.shrink();
        }

        final ad = currentAd;
        
        double? effectiveHeight = widget.height;
        if (effectiveHeight == null) {
          if (widget.slot == 'reward_ad') {
            effectiveHeight = double.infinity;
          } else if (widget.slot == 'home_banner_top' ||
              widget.slot == 'home_banner_bottom') {
            // Standard mobile banner height (55dp)
            effectiveHeight = 55.0;
          } else {
            effectiveHeight = 250.0;
          }
        }

        if (effectiveHeight.isInfinite) {
          return SizedBox.expand(
            child: _buildContent(ad),
          );
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
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  late final ValueNotifier<bool> _isInitialized;
  bool _hasErrorOrTimeout = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _isInitialized = ValueNotifier(false);
    _timeoutTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isInitialized.value) {
        setState(() {
          _hasErrorOrTimeout = true;
        });
      }
    });
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
      _videoController = controller;
      await controller.initialize().timeout(const Duration(seconds: 4));

      if (mounted) {
        _timeoutTimer?.cancel();
        _chewieController = ChewieController(
          videoPlayerController: controller,
          autoPlay: true,
          looping: true,
          showControls: false, // Ad style
          aspectRatio: controller.value.aspectRatio,
        );
        _isInitialized.value = true;
      }
    } catch (e) {
      AdvancedLogger.warn('[AdWidget] Video init failed or timed out: $e');
      if (mounted) {
        setState(() {
          _hasErrorOrTimeout = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _videoController?.dispose();
    _chewieController?.dispose();
    _isInitialized.dispose();
    super.dispose();
  }

  Widget _buildBrandedFallback() {
    return ScaleOnTap(
      onTap: () {
        if (widget.targetUrl.isNotEmpty) {
          launchUrl(
            Uri.parse(widget.targetUrl),
            mode: LaunchMode.externalApplication,
          );
        }
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF0F172A),
              Color(0xFF1E293B),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blueAccent.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  size: 48,
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'iVPN Sponsor Network',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'High-Speed Secure Connection',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              if (!_hasErrorOrTimeout) ...[
                const SizedBox(height: 14),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasErrorOrTimeout) {
      return _buildBrandedFallback();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _isInitialized,
      builder: (context, isInitialized, child) {
        if (!isInitialized || _chewieController == null) {
          return _buildBrandedFallback();
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
          child: Chewie(controller: _chewieController!),
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

    final notifyScript = """
      <script>
        function notifyAdLoaded() {
          try {
            if (window.AdChannel) {
              window.AdChannel.postMessage('ad_loaded');
            }
          } catch(e) {}
        }
        window.addEventListener('load', function() {
          var iframes = document.getElementsByTagName('iframe');
          if (iframes.length > 0) {
            for (var i = 0; i < iframes.length; i++) {
              iframes[i].addEventListener('load', notifyAdLoaded);
            }
          } else {
            notifyAdLoaded();
          }
        });
      </script>
    """;

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
          iframe { border: none; width: 100%; height: 100%; overflow: hidden; display: block; background-color: transparent !important; }
        </style>
      </head>
      <body>
        $content
        $notifyScript
      </body>
      </html>
      """;
    } else {
      if (content.contains("</body>")) {
        content = content.replaceFirst("</body>", "$notifyScript</body>");
      } else {
        content = "$content$notifyScript";
      }
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

  @override
  void initState() {
    super.initState();
    AdvancedLogger.info('[AdWidget] Loading Mobile HTML...');

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'AdChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (message.message == 'ad_loaded') {
            AdvancedLogger.info('[AdWidget] Mobile Ad iframe content loaded successfully.');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            AdvancedLogger.info('[AdWidget] Mobile Wrapper HTML Loaded.');
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            if (url.startsWith('data:') ||
                url.startsWith('about:') ||
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(
      controller: _controller,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{},
    );
  }
}
