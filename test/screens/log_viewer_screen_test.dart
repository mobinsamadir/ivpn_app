import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/screens/log_viewer_screen.dart';
import 'package:ivpn_new/utils/advanced_logger.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    AdvancedLogger.logNotifier.value = [];
  });

  testWidgets('LogViewerScreen renders logs and coloring correctly',
      (WidgetTester tester) async {
    AdvancedLogger.logNotifier.value = [
      '[INFO] Application started',
      '[ERROR] Connection failed',
      '[WARN] Slow network',
      '[DEBUG] Some debug message',
    ];

    await tester.pumpWidget(const MaterialApp(home: LogViewerScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Log Viewer'), findsOneWidget);
    expect(find.textContaining('Application started'), findsOneWidget);
    expect(find.textContaining('Connection failed'), findsOneWidget);

    final errorText =
        tester.widget<Text>(find.textContaining('Connection failed'));
    expect(errorText.style?.color, Colors.red);
  });
}
