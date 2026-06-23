import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/shimmer_config_card.dart';

void main() {
  testWidgets('ShimmerConfigCard renders without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ShimmerConfigCard(),
        ),
      ),
    );

    // Verify container and structure existence
    expect(find.byType(Container), findsWidgets);
    expect(find.byType(Row), findsWidgets);
  });
}
