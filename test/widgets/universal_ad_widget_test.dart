import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/universal_ad_widget.dart';
import 'package:ivpn_new/services/ad_manager_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('UniversalAdWidget handles disabled ad configuration',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await AdManagerService().initialize();
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
}
