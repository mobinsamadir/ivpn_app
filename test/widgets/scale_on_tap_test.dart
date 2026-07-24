import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/scale_on_tap.dart';

void main() {
  testWidgets('ScaleOnTap animation scale down on tap',
      (WidgetTester tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScaleOnTap(
            onTap: () {
              tapped = true;
            },
            child: const Text('Tap Me Content'),
          ),
        ),
      ),
    );

    final widgetFinder = find.byType(ScaleOnTap);
    expect(widgetFinder, findsOneWidget);

    final gestureFinder = find.descendant(
      of: widgetFinder,
      matching: find.byType(GestureDetector),
    );

    // Initial scale is 1.0
    // Use first instead of widget since there might be multiple ScaleTransitions
    ScaleTransition scaleTransition =
        tester.firstWidget(find.byType(ScaleTransition));
    expect(scaleTransition.scale.value, 1.0);

    // Trigger onTapDown
    final gesture = await tester.startGesture(tester.getCenter(gestureFinder));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));

    scaleTransition = tester.firstWidget(find.byType(ScaleTransition));
    expect(scaleTransition.scale.value, lessThan(1.0));

    // Release
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    scaleTransition = tester.firstWidget(find.byType(ScaleTransition));
    expect(scaleTransition.scale.value, 1.0);
  });
}
