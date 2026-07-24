import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/background_ad_service.dart';

void main() {
  testWidgets('BackgroundAdService renders child', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BackgroundAdService(
          child: Text('Background Ad Content'),
        ),
      ),
    );

    expect(find.text('Background Ad Content'), findsOneWidget);
  });
}
