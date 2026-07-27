import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/full_screen_ad_dialog.dart';
import 'package:ivpn_new/services/ad_manager_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('FullScreenAdDialog renders successfully when ads disabled', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await AdManagerService().initialize();
    kEnableAds = false;

    await tester.pumpWidget(
      const MaterialApp(
        home: FullScreenAdDialog(unitId: 'reward_ad'),
      ),
    );

    expect(find.byType(FullScreenAdDialog), findsOneWidget);
  });
}
