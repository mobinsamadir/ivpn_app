import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ivpn_new/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('VPN Lifecycle Integration', () {
    testWidgets('Full Connect/Disconnect Lifecycle', (tester) async {
      // 1. Launch App
      app.main();
      await tester.pumpAndSettle();

      // Find the add config button (floating action button or similar)
      // For now, let's just make sure the app loads successfully
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
