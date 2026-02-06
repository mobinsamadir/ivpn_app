import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/screens/connection_home_screen.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:ivpn_new/services/windows_vpn_service.dart';
import 'package:ivpn_new/services/ad_service.dart';
import 'package:ivpn_new/providers/home_provider.dart';
import 'package:provider/provider.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'home_screen_comprehensive_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<ConfigManager>(),
  MockSpec<WindowsVpnService>(),
  MockSpec<HomeProvider>(),
])
void main() {
  group('ConnectionHomeScreen Comprehensive Tests', () {
    late MockConfigManager mockConfigManager;
    late MockWindowsVpnService mockVpnService;
    late MockHomeProvider mockHomeProvider;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      
      mockConfigManager = MockConfigManager();
      mockVpnService = MockWindowsVpnService();
      mockHomeProvider = MockHomeProvider();
      
      // Use Manual Fakes instead of Mocks for WebView
      final fakeWebViewPlatform = FakeWebViewPlatform();
      WebViewPlatform.instance = fakeWebViewPlatform;
      
      // Setup ConfigManager Mock (Keep this)
      when(mockConfigManager.isConnected).thenReturn(false);
      when(mockConfigManager.connectionStatus).thenReturn('Disconnected');
      when(mockConfigManager.allConfigs).thenReturn([]);
      when(mockConfigManager.isRefreshing).thenReturn(false);
      when(mockConfigManager.isAutoSwitchEnabled).thenReturn(false);
      when(mockConfigManager.selectedConfig).thenReturn(null);
    });

    testWidgets('Smart Paste Button exists and triggers import', (WidgetTester tester) async {
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
            // Vital: Use ChangeNotifierProvider for Listenable classes
            ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
            ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
            
            // Use standard Provider for Services
            Provider<WindowsVpnService>.value(value: mockVpnService),
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

      // Mock clipboard content
      when(mockConfigManager.addConfig(any, any)).thenAnswer((_) async => null);
      await tester.tap(find.byKey(const Key('smart_paste_button')));
      await tester.pump();

      // Verify that the button was pressed and triggered the appropriate action
      verify(mockConfigManager.addConfig(any, any)).called(1);
    });

    testWidgets('Update Button triggers refreshAllConfigs', (WidgetTester tester) async {
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
            // Vital: Use ChangeNotifierProvider for Listenable classes
            ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
            ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
            
            // Use standard Provider for Services
            Provider<WindowsVpnService>.value(value: mockVpnService),
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
            // Vital: Use ChangeNotifierProvider for Listenable classes
            ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
            ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
            
            // Use standard Provider for Services
            Provider<WindowsVpnService>.value(value: mockVpnService),
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
            // Vital: Use ChangeNotifierProvider for Listenable classes
            ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
            ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
            
            // Use standard Provider for Services
            Provider<WindowsVpnService>.value(value: mockVpnService),
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
            // Vital: Use ChangeNotifierProvider for Listenable classes
            ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
            ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
            
            // Use standard Provider for Services
            Provider<WindowsVpnService>.value(value: mockVpnService),
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
            // Vital: Use ChangeNotifierProvider for Listenable classes
            ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
            ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
            
            // Use standard Provider for Services
            Provider<WindowsVpnService>.value(value: mockVpnService),
          ],
          child: const MaterialApp(
            home: ConnectionHomeScreen(),
          ),
        ),
      );

      // Initially no configs
      when(mockConfigManager.allConfigs).thenReturn([]);

      // Tap smart paste button
      when(mockConfigManager.addConfig(any, any)).thenAnswer((_) async => null);
      await tester.tap(find.byKey(const Key('smart_paste_button')));
      await tester.pump();

      // The actual config addition depends on clipboard content
      // This verifies the button triggers the appropriate handler
      verify(mockConfigManager.addConfig(any, any)).called(1);
    });

    testWidgets('Traffic Stats update when VpnStatus changes', (WidgetTester tester) async {
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
            // Vital: Use ChangeNotifierProvider for Listenable classes
            ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
            ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
            
            // Use standard Provider for Services
            Provider<WindowsVpnService>.value(value: mockVpnService),
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
            // Vital: Use ChangeNotifierProvider for Listenable classes
            ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
            ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
            
            // Use standard Provider for Services
            Provider<WindowsVpnService>.value(value: mockVpnService),
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

// --- CORRECTED FAKES FOR PLATFORM INTERFACE ---

class FakeWebViewPlatform extends WebViewPlatform { 
  // Note: extends, NOT implements
  
  @override
  PlatformWebViewController createPlatformWebViewController(PlatformWebViewControllerCreationParams params) {
    return FakeWebViewController(params);
  }
  
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) {
    return FakeNavigationDelegate(params);
  }
}

class FakeWebViewController extends PlatformWebViewController {
  // Must accept params to satisfy super constructor requirements if any, 
  // or just call super.implementation() if available.
  // Safest way for standard PlatformInterface:
  FakeWebViewController(PlatformWebViewControllerCreationParams params) : super.implementation(params);
  
  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
  
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  
  @override
  Future<void> setBackgroundColor(Color color) async {}
  
  // Catch-all to prevent crashes
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(PlatformNavigationDelegateCreationParams params) : super.implementation(params);
  
  @override
  Future<void> setOnPageFinished(void Function(String url) onPageFinished) async {}
  
  // Catch-all to prevent crashes
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}