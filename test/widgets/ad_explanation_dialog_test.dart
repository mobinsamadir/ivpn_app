import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/ad_explanation_dialog.dart';

void main() {
  Widget createTestWidget({required Future<bool> Function() onAdView}) {
    return MaterialApp(
      home: Scaffold(
        body: AdExplanationDialog(onAdView: onAdView),
      ),
    );
  }

  group('AdExplanationDialog', () {
    testWidgets('renders dialog correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget(onAdView: () async => true));

      expect(find.text('Add 1 Hour Time'), findsOneWidget);
      expect(find.textContaining('To keep the service free'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('View Ad'), findsOneWidget);
    });

    testWidgets('clicking Cancel pops dialog with false',
        (WidgetTester tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (ctx) =>
                      AdExplanationDialog(onAdView: () async => true),
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('clicking View Ad calls onAdView and pops with result',
        (WidgetTester tester) async {
      bool? result;
      var onAdViewCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AdExplanationDialog(onAdView: () async {
                    onAdViewCalled = true;
                    await Future.delayed(const Duration(milliseconds: 10));
                    return true;
                  }),
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Ad'), warnIfMissed: false);
      await tester.pump(); // Start the async operation

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(onAdViewCalled, isTrue);

      await tester
          .pumpAndSettle(); // Finish the async operation and close dialog

      expect(result, isTrue);
    });

    testWidgets('clicking View Ad handles exception and pops with false',
        (WidgetTester tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AdExplanationDialog(onAdView: () async {
                    throw Exception('Ad load failed');
                  }),
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Ad'), warnIfMissed: false);
      await tester.pumpAndSettle(); // Handle error and close dialog

      expect(result, isFalse);
    });
  });
}
