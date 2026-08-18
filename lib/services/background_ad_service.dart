import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

// ✅ اصلاح: ایمپورت‌های صحیح در ابتدای فایل
import 'package:webview_flutter/webview_flutter.dart';

class BackgroundAdService extends StatefulWidget {
  final Widget child;

  const BackgroundAdService({super.key, required this.child});

  @override
  State<BackgroundAdService> createState() => _BackgroundAdServiceState();
}

class _BackgroundAdServiceState extends State<BackgroundAdService> {
  final ValueNotifier<WebViewController?> _popunderController = ValueNotifier(null);
  final ValueNotifier<WebViewController?> _socialBarController = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _initBackgroundAds();
    }
  }

  Future<void> _initBackgroundAds() async {
    await _initPopunderAd();
    await _initSocialBarAd();
  }

  Future<void> _initPopunderAd() async {
    if (Platform.isWindows) {
      try {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..enableZoom(false)
          ..setBackgroundColor(Colors.transparent);

        String popunderHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { margin: 0; padding: 0; background: transparent; }
  </style>
</head>
<body>
  <iframe data-aa='2426527' src='https://ad.a-ads.com/2426527' style='border:0px; padding:0; width:100%; height:100%; overflow:hidden;'></iframe>
</body>
</html>
''';

        controller.loadHtmlString(popunderHtml);

        if (mounted) {
          _popunderController.value = controller;
        }
      } catch (e) {
        debugPrint('Error initializing Popunder Ad: $e');
      }
    }
  }

  Future<void> _initSocialBarAd() async {
    if (Platform.isWindows) {
      try {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..enableZoom(false)
          ..setBackgroundColor(Colors.transparent);

        String socialBarHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { margin: 0; padding: 0; background: transparent; }
  </style>
</head>
<body>
  <iframe data-aa='2426527' src='https://ad.a-ads.com/2426527' style='border:0px; padding:0; width:100%; height:100%; overflow:hidden;'></iframe>
</body>
</html>
''';

        controller.loadHtmlString(socialBarHtml);

        if (mounted) {
          _socialBarController.value = controller;
        }
      } catch (e) {
        debugPrint('Error initializing Social Bar Ad: $e');
      }
    }
  }

  @override
  void dispose() {
    _popunderController.dispose();
    _socialBarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      return Stack(
        children: [
          widget.child,
          Positioned(
            top: -1000,
            left: -1000,
            child: SizedBox(
              width: 1,
              height: 1,
              child: ValueListenableBuilder<WebViewController?>(
                valueListenable: _popunderController,
                builder: (context, controller, child) {
                  return controller != null
                      ? WebViewWidget(controller: controller)
                      : const SizedBox.shrink();
                },
              ),
            ),
          ),
          Positioned(
            top: -2000,
            left: -2000,
            child: SizedBox(
              width: 1,
              height: 1,
              child: ValueListenableBuilder<WebViewController?>(
                valueListenable: _socialBarController,
                builder: (context, controller, child) {
                  return controller != null
                      ? WebViewWidget(controller: controller)
                      : const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      );
    } else {
      return widget.child;
    }
  }
}
