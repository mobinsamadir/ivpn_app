import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/background_ad_service.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class DummyWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return DummyWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return DummyWebViewWidget(params);
  }
}

class DummyWebViewController extends PlatformWebViewController {
  DummyWebViewController(super.params) : super.implementation();

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}
}

class DummyWebViewWidget extends PlatformWebViewWidget {
  DummyWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  setUp(() {
    WebViewPlatform.instance = DummyWebViewPlatform();
  });

  group('BackgroundAdService Tests', () {
    testWidgets(
        'BackgroundAdService renders child and initializes without error on Windows',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(
        const MaterialApp(
          home: BackgroundAdService(
            child: Text('Test Child Text'),
          ),
        ),
      );

      expect(find.text('Test Child Text'), findsOneWidget);
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
