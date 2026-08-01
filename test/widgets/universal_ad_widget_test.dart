import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/universal_ad_widget.dart';
import 'package:ivpn_new/services/ad_manager_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:ivpn_new/models/ad_config.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdManagerService().initialize();
    WebViewPlatform.instance = AndroidWebViewPlatform();
  });

  testWidgets('UniversalAdWidget handles disabled ad configuration',
      (WidgetTester tester) async {
    kEnableAds = false;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UniversalAdWidget(slot: 'reward_ad'),
        ),
      ),
    );

    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('UniversalAdWidget renders webview ad', (WidgetTester tester) async {
    kEnableAds = true;
    AdManagerService().configNotifier.value = AdConfig(
      configVersion: 'test',
      globalAdsEnabled: 1,
      ads: {
        'test_webview': AdUnit(
          isEnabled: true,
          type: 'webview',
          mediaSource: 'https://example.com',
          targetUrl: '',
          timerSeconds: 0,
        ),
      },
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UniversalAdWidget(slot: 'test_webview'),
        ),
      ),
    );
    // Don't pumpAndSettle as webview loading might not resolve cleanly in tests
    await tester.pump();

    expect(find.byType(UniversalAdWidget), findsOneWidget);
    // Finds the internally used WebView widget inside _MobileWebView
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // Is loading initially
  });

  testWidgets('UniversalAdWidget renders image ad', (WidgetTester tester) async {
    kEnableAds = true;
    AdManagerService().configNotifier.value = AdConfig(
      configVersion: 'test',
      globalAdsEnabled: 1,
      ads: {
        'test_image': AdUnit(
          isEnabled: true,
          type: 'image',
          mediaSource: 'https://example.com/image.png',
          targetUrl: 'https://example.com',
          timerSeconds: 0,
        ),
      },
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UniversalAdWidget(slot: 'test_image'),
        ),
      ),
    );
    // Don't pumpAndSettle due to CachedNetworkImage internal animations/loading
    await tester.pump();

    expect(find.byType(UniversalAdWidget), findsOneWidget);
    // CircularProgressIndicator shown as placeholder for CachedNetworkImage
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
