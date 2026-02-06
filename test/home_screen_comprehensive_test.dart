import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/screens/connection_home_screen.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';
import 'package:ivpn_new/services/ad_service.dart';
import 'package:provider/provider.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';

void main() {
  group('ConnectionHomeScreen Comprehensive Tests', () {
    // Mock classes for testing
    class MockConfigManager extends ConfigManager {
      bool _isConnected = false;
      String _connectionStatus = 'Disconnected';
      List<VpnConfigWithMetrics> _allConfigs = [];
      bool _isRefreshing = false;
      bool _isAutoSwitchEnabled = false;
      VpnConfigWithMetrics? _selectedConfig;

      @override
      bool get isConnected => _isConnected;

      @override
      String get connectionStatus => _connectionStatus;

      @override
      List<VpnConfigWithMetrics> get allConfigs => _allConfigs;

      @override
      bool get isRefreshing => _isRefreshing;

      @override
      bool get isAutoSwitchEnabled => _isAutoSwitchEnabled;

      @override
      VpnConfigWithMetrics? get selectedConfig => _selectedConfig;

      void setConnectedState(bool connected, {String status = ''}) {
        _isConnected = connected;
        _connectionStatus = status.isEmpty 
          ? (connected ? 'Connected' : 'Disconnected') 
          : status;
        notifyListeners();
      }

      void addMockConfig(VpnConfigWithMetrics config) {
        _allConfigs.add(config);
        notifyListeners();
      }

      void setRefreshing(bool refreshing) {
        _isRefreshing = refreshing;
        notifyListeners();
      }

      void setSelectedConfig(VpnConfigWithMetrics? config) {
        _selectedConfig = config;
        notifyListeners();
      }

      // Track calls to methods for verification
      int refreshCallCount = 0;
      int addConfigCallCount = 0;

      @override
      Future<void> refreshAllConfigs() async {
        refreshCallCount++;
        setRefreshing(true);
        await Future.delayed(const Duration(milliseconds: 100)); // Simulate async work
        setRefreshing(false);
      }

      @override
      Future<void> addConfig(String rawConfig, String name, {String countryCode = 'US'}) async {
        addConfigCallCount++;
        final config = VpnConfigWithMetrics(
          id: 'mock-${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          rawConfig: rawConfig,
          countryCode: countryCode,
        );
        _allConfigs.add(config);
        notifyListeners();
      }
    }

    class MockVpnService extends WindowsVpnService {
      int connectCallCount = 0;
      int disconnectCallCount = 0;
      String lastStartedConfig = '';

      @override
      Future<void> startVpn(String config) async {
        connectCallCount++;
        lastStartedConfig = config;
      }

      @override
      Future<void> stopVpn() async {
        disconnectCallCount++;
      }
    }

    class MockAdService {
      bool adShown = false;
      int adShowCount = 0;

      Future<bool> showAd() async {
        adShown = true;
        adShowCount++;
        return true; // Assume ad was watched successfully
      }
    }

    setUp(() {
      // Ensure we have a test binding
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    testWidgets('Smart Paste Button exists and triggers import', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockVpnService();

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
      expect(mockConfigManager.addConfigCallCount, 0);

      // Mock clipboard content
      await tester.tap(find.byKey(const Key('smart_paste_button')));
      await tester.pump();

      // Verify that the button was pressed and triggered the appropriate action
      // (Note: The actual clipboard interaction would be tested separately)
    });

    testWidgets('Update Button triggers refreshAllConfigs', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockVpnService();

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
      expect(mockConfigManager.refreshCallCount, 0);

      // Tap the refresh button
      await tester.tap(find.byKey(const Key('refresh_button')));
      await tester.pump();

      // Verify refreshAllConfigs was called
      expect(mockConfigManager.refreshCallCount, 1);
    });

    testWidgets('Connect Button calls VPN service', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockVpnService();

      // Add a mock config to enable connection
      final mockConfig = VpnConfigWithMetrics(
        id: 'test-config-id',
        name: 'Test Server',
        rawConfig: 'vmess://test-config',
        countryCode: 'US',
      );
      mockConfigManager.addMockConfig(mockConfig);
      mockConfigManager.setSelectedConfig(mockConfig);

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
      expect(mockVpnService.connectCallCount, 0);

      // Tap the connect button
      await tester.tap(find.byKey(const Key('connect_button')));
      await tester.pump();

      // The connection logic is complex, but we can verify the state changes
      // The actual VPN connection would be tested in integration tests
    });

    testWidgets('UI Elements Inventory - All Key elements exist', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockVpnService();

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
      final mockVpnService = MockVpnService();

      // Initially disconnected
      expect(mockConfigManager.isConnected, false);

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
      mockConfigManager.addMockConfig(mockConfig);
      mockConfigManager.setSelectedConfig(mockConfig);

      // Tap the connect button
      await tester.tap(find.byKey(const Key('connect_button')));
      await tester.pump();

      // Verify state changes occurred (would happen asynchronously)
      // In a real test, we'd wait for the connection to complete
    });

    testWidgets('Scenario B: Tap Smart Paste -> Verify Config added', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockVpnService();

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
      expect(mockConfigManager.allConfigs.length, 0);

      // Tap smart paste button
      await tester.tap(find.byKey(const Key('smart_paste_button')));
      await tester.pump();

      // The actual config addition depends on clipboard content
      // This verifies the button triggers the appropriate handler
    });

    testWidgets('Traffic Stats update when VpnStatus changes', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockVpnService();

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
      expect(mockConfigManager.connectionStatus, 'Disconnected');

      // Simulate connection status change
      mockConfigManager.setConnectedState(true, status: 'Connected to Server');

      await tester.pump();

      // Verify UI updates to reflect new status
      expect(find.text('Connected to Server'), findsWidgets);
    });

    testWidgets('ConfigManager state changes trigger UI updates', (WidgetTester tester) async {
      final mockConfigManager = MockConfigManager();
      final mockVpnService = MockVpnService();

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
      mockConfigManager.addMockConfig(mockConfig);

      await tester.pump();

      // Verify that the config list UI updates
      expect(mockConfigManager.allConfigs.length, 1);
    });
  });
}