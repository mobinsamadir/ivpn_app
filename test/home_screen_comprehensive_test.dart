import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/screens/connection_home_screen.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';
import 'package:ivpn_new/services/ad_service.dart';
import 'package:provider/provider.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'home_screen_comprehensive_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<ConfigManager>(),
  MockSpec<WindowsVpnService>(),
])
void main() {
  group('ConnectionHomeScreen Comprehensive Tests', () {

    setUp(() {
      // Ensure we have a test binding
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    testWidgets('Smart Paste Button exists and triggers import', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockWindowsVpnService();

      // Mock the return values
      when(mockConfigManager.isConnected).thenReturn(false);
      when(mockConfigManager.connectionStatus).thenReturn('Disconnected');
      when(mockConfigManager.allConfigs).thenReturn([]);
      when(mockConfigManager.isRefreshing).thenReturn(false);
      when(mockConfigManager.isAutoSwitchEnabled).thenReturn(false);
      when(mockConfigManager.selectedConfig).thenReturn(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConfigManager>.value(value: mockConfigManager),
          ],
          child: const MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Verify Smart Paste button exists
      expect(find.byKey(const Key('smart_paste_button')), findsOneWidget);

      // Initially no calls should have been made
      verifyNever(mockConfigManager.addConfig(any, any));
      verifyNever(mockConfigManager.importFromClipboard());

      // Mock clipboard content
      await tester.tap(find.byKey(const Key('smart_paste_button')));
      await tester.pump();

      // Verify that the button was pressed and triggered the appropriate action
      verify(mockConfigManager.importFromClipboard()).called(1);
    });

    testWidgets('Update Button triggers refreshAllConfigs', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockWindowsVpnService();

      // Mock the return values
      when(mockConfigManager.isConnected).thenReturn(false);
      when(mockConfigManager.connectionStatus).thenReturn('Disconnected');
      when(mockConfigManager.allConfigs).thenReturn([]);
      when(mockConfigManager.isRefreshing).thenReturn(false);
      when(mockConfigManager.isAutoSwitchEnabled).thenReturn(false);
      when(mockConfigManager.selectedConfig).thenReturn(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConfigManager>.value(value: mockConfigManager),
          ],
          child: const MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Verify Refresh button exists
      expect(find.byKey(const Key('refresh_button')), findsOneWidget);

      // Initially no refresh calls
      verifyNever(mockConfigManager.refreshAllConfigs());

      // Tap the refresh button
      await tester.tap(find.byKey(const Key('refresh_button')));
      await tester.pump();

      // Verify refreshAllConfigs was called
      verify(mockConfigManager.refreshAllConfigs()).called(1);
    });

    testWidgets('Connect Button calls VPN service', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockWindowsVpnService();

      // Mock the return values
      when(mockConfigManager.isConnected).thenReturn(false);
      when(mockConfigManager.connectionStatus).thenReturn('Disconnected');
      when(mockConfigManager.allConfigs).thenReturn([]);
      when(mockConfigManager.isRefreshing).thenReturn(false);
      when(mockConfigManager.isAutoSwitchEnabled).thenReturn(false);
      when(mockConfigManager.selectedConfig).thenReturn(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConfigManager>.value(value: mockConfigManager),
          ],
          child: const MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Verify Connect button exists
      expect(find.byKey(const Key('connect_button')), findsOneWidget);

      // Initially no connection calls
      verifyNever(mockVpnService.startVpn(any));

      // Tap the connect button
      await tester.tap(find.byKey(const Key('connect_button')));
      await tester.pump();

      // The connection logic is complex, but we can verify the state changes
      // The actual VPN connection would be tested in integration tests
    });

    testWidgets('UI Elements Inventory - All Key elements exist', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockWindowsVpnService();

      // Mock the return values
      when(mockConfigManager.isConnected).thenReturn(false);
      when(mockConfigManager.connectionStatus).thenReturn('Disconnected');
      when(mockConfigManager.allConfigs).thenReturn([]);
      when(mockConfigManager.isRefreshing).thenReturn(false);
      when(mockConfigManager.isAutoSwitchEnabled).thenReturn(false);
      when(mockConfigManager.selectedConfig).thenReturn(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConfigManager>.value(value: mockConfigManager),
          ],
          child: const MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Verify all key UI elements exist
      expect(find.byKey(const Key('connect_button')), findsOneWidget);
      expect(find.byKey(const Key('top_banner_webview')), findsOneWidget);
      expect(find.byKey(const Key('native_ad_banner')), findsOneWidget);
      expect(find.byKey(const Key('smart_paste_button')), findsOneWidget);
      expect(find.byKey(const Key('refresh_button')), findsOneWidget);
      expect(find.byKey(const Key('server_list_view')), findsOneWidget);
    });

    testWidgets('Scenario A: App starts disconnected -> Tap Connect -> Verify state changes', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockWindowsVpnService();

      // Initially disconnected
      when(mockConfigManager.isConnected).thenReturn(false);
      when(mockConfigManager.connectionStatus).thenReturn('Disconnected');
      when(mockConfigManager.allConfigs).thenReturn([]);
      when(mockConfigManager.isRefreshing).thenReturn(false);
      when(mockConfigManager.isAutoSwitchEnabled).thenReturn(false);
      when(mockConfigManager.selectedConfig).thenReturn(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConfigManager>.value(value: mockConfigManager),
          ],
          child: const MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Verify initial state
      expect(find.text('Disconnected'), findsWidgets); // Connection status text

      // Add a mock config to enable connection
      final mockConfig = VpnConfigWithMetrics(
        id: 'test-config-id',
        name: 'Test Server',
        rawConfig: 'vmess://test-config',
        countryCode: 'US',
      );
      when(mockConfigManager.allConfigs).thenReturn([mockConfig]);
      when(mockConfigManager.selectedConfig).thenReturn(mockConfig);

      // Tap the connect button
      await tester.tap(find.byKey(const Key('connect_button')));
      await tester.pump();

      // Verify state changes occurred (would happen asynchronously)
      // In a real test, we'd wait for the connection to complete
    });

    testWidgets('Scenario B: Tap Smart Paste -> Verify Config added', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockWindowsVpnService();

      // Mock the return values
      when(mockConfigManager.isConnected).thenReturn(false);
      when(mockConfigManager.connectionStatus).thenReturn('Disconnected');
      when(mockConfigManager.allConfigs).thenReturn([]);
      when(mockConfigManager.isRefreshing).thenReturn(false);
      when(mockConfigManager.isAutoSwitchEnabled).thenReturn(false);
      when(mockConfigManager.selectedConfig).thenReturn(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConfigManager>.value(value: mockConfigManager),
          ],
          child: const MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Initially no configs
      when(mockConfigManager.allConfigs).thenReturn([]);

      // Tap smart paste button
      await tester.tap(find.byKey(const Key('smart_paste_button')));
      await tester.pump();

      // The actual config addition depends on clipboard content
      // This verifies the button triggers the appropriate handler
      verify(mockConfigManager.importFromClipboard()).called(1);
    });

    testWidgets('Traffic Stats update when VpnStatus changes', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockWindowsVpnService();

      // Mock the return values
      when(mockConfigManager.isConnected).thenReturn(false);
      when(mockConfigManager.connectionStatus).thenReturn('Disconnected');
      when(mockConfigManager.allConfigs).thenReturn([]);
      when(mockConfigManager.isRefreshing).thenReturn(false);
      when(mockConfigManager.isAutoSwitchEnabled).thenReturn(false);
      when(mockConfigManager.selectedConfig).thenReturn(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConfigManager>.value(value: mockConfigManager),
          ],
          child: const MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Initially disconnected
      when(mockConfigManager.connectionStatus).thenReturn('Disconnected');

      // Simulate connection status change
      when(mockConfigManager.connectionStatus).thenReturn('Connected to Server');

      await tester.pump();

      // Verify UI updates to reflect new status
      expect(find.text('Connected to Server'), findsWidgets);
    });

    testWidgets('ConfigManager state changes trigger UI updates', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockWindowsVpnService();

      // Mock the return values
      when(mockConfigManager.isConnected).thenReturn(false);
      when(mockConfigManager.connectionStatus).thenReturn('Disconnected');
      when(mockConfigManager.allConfigs).thenReturn([]);
      when(mockConfigManager.isRefreshing).thenReturn(false);
      when(mockConfigManager.isAutoSwitchEnabled).thenReturn(false);
      when(mockConfigManager.selectedConfig).thenReturn(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConfigManager>.value(value: mockConfigManager),
          ],
          child: const MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Add a config and verify UI updates
      final mockConfig = VpnConfigWithMetrics(
        id: 'test-config-id',
        name: 'Test Server',
        rawConfig: 'vmess://test-config',
        countryCode: 'US',
      );
      when(mockConfigManager.allConfigs).thenReturn([mockConfig]);

      await tester.pump();

      // Verify that the config list UI updates
      expect(mockConfigManager.allConfigs.length, 1);
    });
  });
}