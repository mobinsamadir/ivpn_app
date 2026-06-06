import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

// ✅ اصلاح: ایمپورت‌های صحیح در ابتدای فایل
import 'package:webview_windows/webview_windows.dart';

class BackgroundAdService extends StatefulWidget {
  final Widget child;

  const BackgroundAdService({super.key, required this.child});

  @override
  State<BackgroundAdService> createState() => _BackgroundAdServiceState();
}

class _BackgroundAdServiceState extends State<BackgroundAdService> {
  // تعریف متغیرها با تایپ دقیق (به جای dynamic)
  WebviewController? _popunderController;
  WebviewController? _socialBarController;

  @override
  void initState() {
    super.initState();
    // فقط در ویندوز تبلیغات پس‌زمینه لود می‌شوند
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
        final controller = WebviewController();
        await controller.initialize();

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

        await controller.loadStringContent(popunderHtml);

        if (mounted) {
          setState(() {
            _popunderController = controller;
          });
        }
      } catch (e) {
        debugPrint('Error initializing Popunder Ad: $e');
      }
    }
  }

  Future<void> _initSocialBarAd() async {
    if (Platform.isWindows) {
      try {
        final controller = WebviewController();
        await controller.initialize();

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

        await controller.loadStringContent(socialBarHtml);

        if (mounted) {
          setState(() {
            _socialBarController = controller;
          });
        }
      } catch (e) {
        debugPrint('Error initializing Social Bar Ad: $e');
      }
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      _popunderController?.dispose();
      _socialBarController?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // اگر ویندوز است، تبلیغات مخفی را در Stack قرار بده
    if (Platform.isWindows) {
      return Stack(
        children: [
          widget.child,

          // Hidden Popunder
          Positioned(
            top: -1000,
            left: -1000,
            child: SizedBox(
              width: 1,
              height: 1,
              // فقط زمانی که کنترلر آماده است وب‌ویو را نشان بده
              child: _popunderController != null &&
                      _popunderController!.value.isInitialized
                  ? Webview(_popunderController!)
                  : const SizedBox.shrink(),
            ),
          ),

          // Hidden Social Bar
          Positioned(
            top: -2000,
            left: -2000,
            child: SizedBox(
              width: 1,
              height: 1,
              child: _socialBarController != null &&
                      _socialBarController!.value.isInitialized
                  ? Webview(_socialBarController!)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      );
    } else {
      // در موبایل (اندروید/iOS) فقط برنامه اصلی بدون تبلیغات پس‌زمینه
      return widget.child;
    }
  }
}
