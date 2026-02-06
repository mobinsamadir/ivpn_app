import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/screens/connection_home_screen.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:provider/provider.dart';

void main() {
  group('ConnectionHomeScreen Widget Tests', () {
    testWidgets('UI elements exist and are interactive', (WidgetTester tester) async {
      // Mock services for testing
      final mockConfigManager = MockConfigManager();

      // Pump the widget wrapped in MultiProvider with mocked services
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConfigManager>.value(value: mockConfigManager),
          ],
          child: MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Test Case 1: Structure - Find UI elements by Key
      expect(find.byKey(const Key('connect_button')), findsOneWidget);
      expect(find.byKey(const Key('top_banner_webview')), findsOneWidget);
      expect(find.byKey(const Key('native_ad_banner')), findsOneWidget);
    });

    testWidgets('Smart Paste button interaction shows dialog', (WidgetTester tester) async {
      // Mock services for testing
      final mockConfigManager = MockConfigManager();

      // Pump the widget wrapped in MultiProvider with mocked services
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConfigManager>.value(value: mockConfigManager),
          ],
          child: MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Test Case 2: Interaction - Tap smart paste button and verify dialog appears
      await tester.tap(find.byKey(const Key('smart_paste_button')));
      await tester.pump(); // Trigger rebuild
      
      // Look for AlertDialog or similar dialog that would appear after tapping smart paste
      expect(find.byType(Dialog), findsOneWidget);
    });
  });
}

// Mock classes for testing
class MockConfigManager extends ConfigManager {
  @override
  bool get isConnected => false;
  
  @override
  String get connectionStatus => 'Disconnected';
  
  @override
  List<dynamic> get allConfigs => [];
  
  @override
  List<dynamic> get validatedConfigs => [];
  
  @override
  List<dynamic> get favoriteConfigs => [];
  
  @override
  bool get isRefreshing => false;
  
  @override
  bool get isAutoSwitchEnabled => false;
}