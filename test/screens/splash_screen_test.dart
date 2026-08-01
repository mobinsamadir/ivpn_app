import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/screens/splash_screen.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('SplashScreen renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ConfigManager()),
        ],
        child: const MaterialApp(
          home: SplashScreen(),
        ),
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byIcon(Icons.vpn_lock), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
