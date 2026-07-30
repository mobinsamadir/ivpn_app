import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ivpn_new/screens/settings_screen.dart';
import 'package:ivpn_new/providers/theme_provider.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SettingsScreen renders correctly', (WidgetTester tester) async {
    final themeProvider = ThemeProvider();
    final configManager = ConfigManager();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<ConfigManager>.value(value: configManager),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });
}
