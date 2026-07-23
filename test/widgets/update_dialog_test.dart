import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/update_dialog.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

void main() {
  group('UpdateDialog', () {
    testWidgets('renders dialog correctly with Markdown',
        (WidgetTester tester) async {
      var onUpdateCalled = false;
      const version = '1.2.3';
      const releaseNotes = '# Great news!\n* Feature 1\n* Feature 2';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateDialog(
              version: version,
              releaseNotes: releaseNotes,
              onUpdate: () {
                onUpdateCalled = true;
              },
            ),
          ),
        ),
      );

      // Check texts
      expect(find.text('New Update Available'), findsOneWidget);
      expect(find.text('Version $version'), findsOneWidget);
      expect(find.text("What's New:"), findsOneWidget);

      // Check Markdown Body
      expect(find.byType(MarkdownBody), findsOneWidget);

      // Check buttons
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);

      // Tap update now
      await tester.tap(find.text('Update Now'), warnIfMissed: false);
      await tester.pump();
      expect(onUpdateCalled, isTrue);
    });

    testWidgets('clicking Later dismisses the dialog',
        (WidgetTester tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => UpdateDialog(
                    version: '1.0.0',
                    releaseNotes: 'notes',
                    onUpdate: () {},
                  ),
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(find.byType(UpdateDialog), findsNothing);
      expect(result, isNull);
    });
  });
}
