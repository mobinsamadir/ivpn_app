import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/background_ad_service.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('BackgroundAdService Extra Coverage', () {
    setUpAll(() {
      WebViewPlatform.instance = AndroidWebViewPlatform();
    });
    testWidgets('renders child on non-Windows', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BackgroundAdService(
            child: const Text('Child'),
          ),
        ),
      );
      expect(find.text('Child'), findsOneWidget);
    });
  });
}
