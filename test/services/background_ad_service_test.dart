import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/background_ad_service.dart';

void main() {
  testWidgets('BackgroundAdService renders child and initializes without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BackgroundAdService(
          child: Text('Test Child Text'),
        ),
      ),
    );

    expect(find.text('Test Child Text'), findsOneWidget);

    // Test that the widget can be pumped again without errors
    await tester.pumpAndSettle();
  });
}
