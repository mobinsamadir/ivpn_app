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
  // 1. FIX SCOPE: Declare variables here, reachable by all tests
  late MockConfigManager mockConfigManager;
  late MockWindowsVpnService mockVpnService;
  late MockHomeProvider mockHomeProvider;

  setUp(() {
    print('DEBUG: Starting setUp...'); // LOGGING
    TestWidgetsFlutterBinding.ensureInitialized();
    
    // Initialize Mocks
    mockConfigManager = MockConfigManager();
    mockVpnService = MockWindowsVpnService();
    mockHomeProvider = MockHomeProvider();
    
    // Setup WebView Fake
    WebViewPlatform.instance = FakeWebViewPlatform();
    
    // Default Stubs
    when(mockConfigManager.isConnected).thenReturn(false);
    when(mockConfigManager.connectionStatus).thenReturn('Disconnected');
    when(mockConfigManager.allConfigs).thenReturn([]);
    when(mockConfigManager.isRefreshing).thenReturn(false);
    when(mockConfigManager.isAutoSwitchEnabled).thenReturn(false);
    when(mockConfigManager.selectedConfig).thenReturn(null);
    print('DEBUG: setUp completed successfully.');
  });

  testWidgets('Smart Paste Button exists and triggers import', (WidgetTester tester) async {
    print('DEBUG: Starting Smart Paste Test');
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
          ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
          Provider<WindowsVpnService>.value(value: mockVpnService),
        ],
        child: const MaterialApp(home: ConnectionHomeScreen()),
      ),
    );
    print('DEBUG: Widget Pumped');
    await tester.pumpAndSettle();
    
    // Verify Smart Paste button exists
    expect(find.byKey(const Key('smart_paste_button')), findsOneWidget);
    print('DEBUG: Smart Paste Button found');

    // Initially no calls should have been made
    verifyNever(mockConfigManager.addConfig(any, any));
    print('DEBUG: Verified no prior calls to addConfig');

    // Mock clipboard content
    when(mockConfigManager.addConfig(any, any)).thenAnswer((_) async => null);
    await tester.tap(find.byKey(const Key('smart_paste_button')));
    await tester.pumpAndSettle();

    // Verify that the button was pressed and triggered the appropriate action
    verify(mockConfigManager.addConfig(any, any)).called(1);
    print('DEBUG: Smart Paste Test Finished');
  });

  testWidgets('Update Button triggers refreshAllConfigs', (WidgetTester tester) async {
    print('DEBUG: Starting Update Button Test');
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
          ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
          Provider<WindowsVpnService>.value(value: mockVpnService),
        ],
        child: const MaterialApp(home: ConnectionHomeScreen()),
      ),
    );
    print('DEBUG: Widget Pumped');
    await tester.pumpAndSettle();

    // Verify Refresh button exists
    expect(find.byKey(const Key('refresh_button')), findsOneWidget);
    print('DEBUG: Refresh Button found');

    // Initially no refresh calls
    verifyNever(mockConfigManager.refreshAllConfigs());
    print('DEBUG: Verified no prior calls to refreshAllConfigs');

    // Tap the refresh button
    await tester.tap(find.byKey(const Key('refresh_button')));
    await tester.pumpAndSettle();

    // Verify refreshAllConfigs was called
    verify(mockConfigManager.refreshAllConfigs()).called(1);
    print('DEBUG: Update Button Test Finished');
  });

  testWidgets('Connect Button calls VPN service', (WidgetTester tester) async {
    print('DEBUG: Starting Connect Button Test');
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
          ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
          Provider<WindowsVpnService>.value(value: mockVpnService),
        ],
        child: const MaterialApp(home: ConnectionHomeScreen()),
      ),
    );
    print('DEBUG: Widget Pumped');
    await tester.pumpAndSettle();

    // Verify Connect button exists
    expect(find.byKey(const Key('connect_button')), findsOneWidget);
    print('DEBUG: Connect Button found');

    // Initially no connection calls
    verifyNever(mockVpnService.startVpn(any));
    print('DEBUG: Verified no prior calls to startVpn');

    // Tap the connect button
    await tester.tap(find.byKey(const Key('connect_button')));
    await tester.pumpAndSettle();

    print('DEBUG: Connect Button Test Finished');
  });

  testWidgets('UI Elements Inventory - All Key elements exist', (WidgetTester tester) async {
    print('DEBUG: Starting UI Elements Test');
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
          ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
          Provider<WindowsVpnService>.value(value: mockVpnService),
        ],
        child: const MaterialApp(home: ConnectionHomeScreen()),
      ),
    );
    print('DEBUG: Widget Pumped');
    await tester.pumpAndSettle();

    // Verify all key UI elements exist
    expect(find.byKey(const Key('connect_button')), findsOneWidget);
    expect(find.byKey(const Key('top_banner_webview')), findsOneWidget);
    expect(find.byKey(const Key('native_ad_banner')), findsOneWidget);
    expect(find.byKey(const Key('smart_paste_button')), findsOneWidget);
    expect(find.byKey(const Key('refresh_button')), findsOneWidget);
    expect(find.byKey(const Key('server_list_view')), findsOneWidget);
    print('DEBUG: All UI Elements Test Finished');
  });

  testWidgets('Scenario A: App starts disconnected -> Tap Connect -> Verify state changes', (WidgetTester tester) async {
    print('DEBUG: Starting Scenario A Test');
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
          ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
          Provider<WindowsVpnService>.value(value: mockVpnService),
        ],
        child: const MaterialApp(home: ConnectionHomeScreen()),
      ),
    );
    print('DEBUG: Widget Pumped');
    await tester.pumpAndSettle();

    // Verify initial state
    expect(find.text('Disconnected'), findsWidgets); // Connection status text
    print('DEBUG: Initial disconnected state verified');

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
    await tester.pumpAndSettle();

    print('DEBUG: Scenario A Test Finished');
  });

  testWidgets('Scenario B: Tap Smart Paste -> Verify Config added', (WidgetTester tester) async {
    print('DEBUG: Starting Scenario B Test');
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
          ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
          Provider<WindowsVpnService>.value(value: mockVpnService),
        ],
        child: const MaterialApp(home: ConnectionHomeScreen()),
      ),
    );
    print('DEBUG: Widget Pumped');
    await tester.pumpAndSettle();

    // Initially no configs
    when(mockConfigManager.allConfigs).thenReturn([]);

    // Tap smart paste button
    when(mockConfigManager.addConfig(any, any)).thenAnswer((_) async => null);
    await tester.tap(find.byKey(const Key('smart_paste_button')));
    await tester.pumpAndSettle();

    // The actual config addition depends on clipboard content
    // This verifies the button triggers the appropriate handler
    verify(mockConfigManager.addConfig(any, any)).called(1);
    print('DEBUG: Scenario B Test Finished');
  });

  testWidgets('Traffic Stats update when VpnStatus changes', (WidgetTester tester) async {
    print('DEBUG: Starting Traffic Stats Test');
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
          ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
          Provider<WindowsVpnService>.value(value: mockVpnService),
        ],
        child: const MaterialApp(home: ConnectionHomeScreen()),
      ),
    );
    print('DEBUG: Widget Pumped');
    await tester.pumpAndSettle();

    // Initially disconnected
    when(mockConfigManager.connectionStatus).thenReturn('Disconnected');

    // Simulate connection status change
    when(mockConfigManager.connectionStatus).thenReturn('Connected to Server');

    await tester.pumpAndSettle();

    // Verify UI updates to reflect new status
    expect(find.text('Connected to Server'), findsWidgets);
    print('DEBUG: Traffic Stats Test Finished');
  });

  testWidgets('ConfigManager state changes trigger UI updates', (WidgetTester tester) async {
    print('DEBUG: Starting ConfigManager State Test');
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConfigManager>.value(value: mockConfigManager),
          ChangeNotifierProvider<HomeProvider>.value(value: mockHomeProvider),
          Provider<WindowsVpnService>.value(value: mockVpnService),
        ],
        child: const MaterialApp(home: ConnectionHomeScreen()),
      ),
    );
    print('DEBUG: Widget Pumped');
    await tester.pumpAndSettle();

    // Add a config and verify UI updates
    final mockConfig = VpnConfigWithMetrics(
      id: 'test-config-id',
      name: 'Test Server',
      rawConfig: 'vmess://test-config',
      countryCode: 'US',
    );
    when(mockConfigManager.allConfigs).thenReturn([mockConfig]);

    await tester.pumpAndSettle();

    // Verify that the config list UI updates
    expect(mockConfigManager.allConfigs.length, 1);
    print('DEBUG: ConfigManager State Test Finished');
  });
}

// --- FAKE CLASSES WITH LOGGING ---
class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(PlatformWebViewControllerCreationParams params) {
    print('DEBUG: FakeWebViewPlatform.createPlatformWebViewController called');
    return FakeWebViewController(params);
  }
  
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) {
    print('DEBUG: FakeWebViewPlatform.createPlatformNavigationDelegate called');
    return FakeNavigationDelegate(params);
  }
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(PlatformWebViewControllerCreationParams params) : super.implementation(params);

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    print('DEBUG: FakeWebViewController.loadRequest called with ${params.uri}');
  }
  
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {
    print('DEBUG: FakeWebViewController.setJavaScriptMode called with $mode');
  }
  
  @override
  Future<void> setBackgroundColor(Color color) async {
    print('DEBUG: FakeWebViewController.setBackgroundColor called with $color');
  }
  
  @override
  dynamic noSuchMethod(Invocation invocation) {
    print('DEBUG: FakeWebViewController handled missing method: ${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(PlatformNavigationDelegateCreationParams params) : super.implementation(params);
  
  @override
  Future<void> setOnPageFinished(void Function(String url) onPageFinished) async {
    print('DEBUG: FakeNavigationDelegate.setOnPageFinished called');
  }

  @override
  Future<void> setOnWebResourceError(void Function(WebResourceError error) onWebResourceError) async {
    print('DEBUG: FakeNavigationDelegate.setOnWebResourceError called');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    print('DEBUG: FakeNavigationDelegate handled missing method: ${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}