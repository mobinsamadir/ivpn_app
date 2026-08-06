import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/screens/connection_home_screen.dart';
import '../services/mock_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ConnectionHomeScreen loads and builds correctly', (WidgetTester tester) async {
    final mockConfigManager = MockConfigManager();
    final mockNativeVpnService = MockNativeVpnService();
    final mockFunnelService = MockFunnelService();
    final mockEphemeralTester = MockEphemeralTester();
    final mockAdManagerService = MockAdManagerService();
    final mockConnectivityService = MockConnectivityService();
    final mockConfigGistService = MockConfigGistService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionHomeScreen(
            configManager: mockConfigManager,
            nativeVpnService: mockNativeVpnService,
            funnelService: mockFunnelService,
            ephemeralTester: mockEphemeralTester,
            adManagerService: mockAdManagerService,
            connectivityService: mockConnectivityService,
            configGistService: mockConfigGistService,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 5));

    expect(find.byType(ConnectionHomeScreen), findsOneWidget);
  });
}
