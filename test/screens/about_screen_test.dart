import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/screens/about_screen.dart';

void main() {
  testWidgets('AboutScreen renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));

    expect(find.text('About US'), findsOneWidget);
    expect(find.text('iVPN'), findsOneWidget);
    expect(find.text('نسخه 1.0.0'), findsOneWidget);
    expect(find.text('کانال تلگرام ما'), findsOneWidget);
  });
}
