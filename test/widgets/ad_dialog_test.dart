import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/ad_dialog.dart';
import 'package:ivpn_new/widgets/universal_ad_widget.dart';

void main() {
  testWidgets('AdDialog renders correctly and has a timer', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdDialog(),
        ),
      ),
    );

    expect(find.text('Sponsored Content'), findsOneWidget);
    expect(find.byType(UniversalAdWidget), findsOneWidget);

    // Check initial button text
    expect(find.textContaining('Please wait'), findsOneWidget);

    // Fast forward time to let timer expire
    await tester.pumpAndSettle(const Duration(seconds: 15));

    expect(find.text('Close & Connect'), findsOneWidget);
  });
}
