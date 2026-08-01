import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/full_screen_ad_dialog.dart';
import 'package:ivpn_new/services/ad_manager_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdManagerService().initialize();
    WebViewPlatform.instance = AndroidWebViewPlatform();
  });

  testWidgets('FullScreenAdDialog renders successfully when ads disabled',
      (WidgetTester tester) async {
    kEnableAds = false;

    await tester.pumpWidget(
      const MaterialApp(
        home: FullScreenAdDialog(unitId: 'reward_ad'),
      ),
    );

    expect(find.byType(FullScreenAdDialog), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('FullScreenAdDialog renders with ads enabled and countdown',
      (WidgetTester tester) async {
    kEnableAds = true;

    await tester.pumpWidget(
      const MaterialApp(
        home: FullScreenAdDialog(unitId: 'reward_ad'),
      ),
    );

    // Initial state
    expect(find.text('Premium Connection'), findsOneWidget);
    expect(find.text('15s'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    // Fast forward 5 seconds
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('10s'), findsOneWidget);

    // Fast forward remaining 10 seconds
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('0s'), findsNothing); // Should disappear when <= 0
    expect(find.text('Thank you! You can now close this ad.'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Tap close button
    await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
    await tester.pumpAndSettle();
  });
}
