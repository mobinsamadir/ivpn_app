import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ivpn_new/screens/connection_home_screen.dart';
import 'package:ivpn_new/services/native_vpn_service.dart';
import 'package:ivpn_new/services/funnel_service.dart';
import 'package:ivpn_new/services/testers/ephemeral_tester.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:ivpn_new/services/ad_manager_service.dart';
import 'package:ivpn_new/services/access_manager.dart';
import 'package:ivpn_new/services/connectivity_service.dart';
import 'package:ivpn_new/services/update_service_wrapper.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

// --- MOCKS ---
class MockNativeVpnService extends Mock implements NativeVpnService {}
class MockFunnelService extends Mock implements FunnelService {}
class MockEphemeralTester extends Mock implements EphemeralTester {}
class MockConfigManager extends Mock implements ConfigManager {}
class MockAdManagerService extends Mock implements AdManagerService {}
class MockAccessManager extends Mock implements AccessManager {}
class MockConnectivityService extends Mock implements ConnectivityService {}
class MockUpdateServiceWrapper extends Mock implements UpdateServiceWrapper {}

// --- FAKE WEBVIEW ---
class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(PlatformWebViewControllerCreationParams params) {
    return FakeWebViewController(params);
  }
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) {
    return FakeNavigationDelegate(params);
  }
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) {
    return FakeWebViewWidget(params);
  }
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();
  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> clearCache() async {}
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();
  @override
  Future<void> setOnPageFinished(void Function(String url) onPageFinished) async {}
  @override
  Future<void> setOnWebResourceError(void Function(WebResourceError error) onWebResourceError) async {}
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class FakeBuildContext extends Fake implements BuildContext {}
class FakeVpnConfigWithMetrics extends Fake implements VpnConfigWithMetrics {}

void main() {
  late MockNativeVpnService mockVpnService;
  late MockFunnelService mockFunnelService;
  late MockEphemeralTester mockEphemeralTester;
  late MockConfigManager mockConfigManager;
  late MockAdManagerService mockAdManagerService;
  late MockAccessManager mockAccessManager;
  late MockConnectivityService mockConnectivityService;
  late MockUpdateServiceWrapper mockUpdateServiceWrapper;

  late StreamController<String> funnelProgressController;
  late StreamController<String> vpnStatusController;
  // Capture listeners for AccessManager updates
  final accessListeners = <VoidCallback>[];

  setUpAll(() {
    registerFallbackValue(FakeBuildContext());
    registerFallbackValue(FakeVpnConfigWithMetrics());
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    WebViewPlatform.instance = FakeWebViewPlatform();

    mockVpnService = MockNativeVpnService();
    mockFunnelService = MockFunnelService();
    mockEphemeralTester = MockEphemeralTester();
    mockConfigManager = MockConfigManager();
    mockAdManagerService = MockAdManagerService();
    mockAccessManager = MockAccessManager();
    mockConnectivityService = MockConnectivityService();
    mockUpdateServiceWrapper = MockUpdateServiceWrapper();

    funnelProgressController = StreamController<String>.broadcast();
    vpnStatusController = StreamController<String>.broadcast();
    accessListeners.clear();

    // Default Stubs
    when(() => mockAdManagerService.initialize()).thenAnswer((_) async {});
    when(() => mockAccessManager.init()).thenAnswer((_) async {});

    // Capture listeners
    when(() => mockAccessManager.addListener(any())).thenAnswer((invocation) {
      accessListeners.add(invocation.positionalArguments[0] as VoidCallback);
    });
    when(() => mockAccessManager.removeListener(any())).thenAnswer((invocation) {
      accessListeners.remove(invocation.positionalArguments[0] as VoidCallback);
    });

    when(() => mockAccessManager.hasAccess).thenReturn(true);
    when(() => mockAccessManager.remainingTime).thenReturn(const Duration(hours: 1));

    when(() => mockConfigManager.stopVpnCallback = any()).thenReturn(null);
    when(() => mockConfigManager.onAutoSwitch = any()).thenReturn(null);

    when(() => mockFunnelService.progressStream).thenAnswer((_) => funnelProgressController.stream);
    when(() => mockVpnService.connectionStatusStream).thenAnswer((_) => vpnStatusController.stream);
    when(() => mockVpnService.disconnect()).thenAnswer((_) async {});
    when(() => mockVpnService.isAdmin()).thenAnswer((_) async => true);

    when(() => mockConfigManager.allConfigs).thenReturn([]);
    when(() => mockConfigManager.validatedConfigs).thenReturn([]);
    when(() => mockConfigManager.favoriteConfigs).thenReturn([]);
    when(() => mockConfigManager.selectedConfig).thenReturn(null);
    when(() => mockConfigManager.isConnected).thenReturn(false);
    when(() => mockConfigManager.connectionStatus).thenReturn('Disconnected');
    when(() => mockConfigManager.isAutoSwitchEnabled).thenReturn(true);
    when(() => mockConfigManager.fetchStartupConfigs()).thenAnswer((_) async => false);

    // Add Listener to ConfigManager (ChangeNotifier)
    when(() => mockConfigManager.addListener(any())).thenReturn(null);
    when(() => mockConfigManager.removeListener(any())).thenReturn(null);

    // Connectivity & Update
    when(() => mockConnectivityService.hasInternet()).thenAnswer((_) async => true);
    when(() => mockUpdateServiceWrapper.checkForUpdatesSilently(any())).thenAnswer((_) async {});
    when(() => mockAdManagerService.fetchLatestAds()).thenAnswer((_) async {});
  });

  tearDown(() {
    funnelProgressController.close();
    vpnStatusController.close();
  });

  Widget createWidget() {
    return MaterialApp(
      home: ConnectionHomeScreen(
        nativeVpnService: mockVpnService,
        funnelService: mockFunnelService,
        ephemeralTester: mockEphemeralTester,
        configManager: mockConfigManager,
        adManagerService: mockAdManagerService,
        accessManager: mockAccessManager,
        connectivityService: mockConnectivityService,
        updateServiceWrapper: mockUpdateServiceWrapper,
      ),
    );
  }

  group('ConnectionHomeScreen Component Tests', () {
    testWidgets('Connect Button exists and renders correctly in disconnected state', (tester) async {
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      final connectTextFinder = find.text('CONNECT');
      expect(connectTextFinder, findsOneWidget);

      final iconFinder = find.byIcon(Icons.power_settings_new);
      expect(iconFinder, findsOneWidget);
    });

    testWidgets('Connect Button triggers connection logic when tapped', (tester) async {
       final config = VpnConfigWithMetrics(
          id: 'test_1',
          rawConfig: 'vmess://...',
          name: 'Test Server',
          addedDate: DateTime.now()
       );
       when(() => mockConfigManager.allConfigs).thenReturn([config]);
       when(() => mockConfigManager.validatedConfigs).thenReturn([config]);
       when(() => mockConfigManager.getBestConfig()).thenAnswer((_) async => config);
       when(() => mockConfigManager.connectWithSmartFailover()).thenAnswer((_) async {});
       when(() => mockConfigManager.connectionStatus).thenReturn('Disconnected');
       when(() => mockConfigManager.setConnected(any(), status: any(named: 'status'))).thenReturn(null);
       when(() => mockConfigManager.selectConfig(any())).thenReturn(null);

       await tester.pumpWidget(createWidget());
       await tester.pumpAndSettle();

       await tester.tap(find.text('CONNECT'));
       await tester.pump();

       verify(() => mockConfigManager.connectWithSmartFailover()).called(1);
    });

    testWidgets('UI updates to Connected state when VPN status changes', (tester) async {
       when(() => mockConfigManager.isConnected).thenReturn(false);

       await tester.pumpWidget(createWidget());
       await tester.pumpAndSettle();

       expect(find.text('Disconnected'), findsOneWidget);

       var isConnected = false;
       var status = 'Disconnected';

       when(() => mockConfigManager.isConnected).thenAnswer((_) => isConnected);
       when(() => mockConfigManager.connectionStatus).thenAnswer((_) => status);
       when(() => mockConfigManager.setConnected(any(), status: any(named: 'status')))
         .thenAnswer((invocation) {
            isConnected = invocation.positionalArguments[0] as bool;
            status = invocation.namedArguments[Symbol('status')] as String;
         });

       vpnStatusController.add('CONNECTED');
       await tester.pump();
       await tester.pump(const Duration(seconds: 4));
       await tester.pumpAndSettle();

       expect(find.text('Connected'), findsOneWidget);
       expect(find.text('DISCONNECT'), findsOneWidget);
    });

    testWidgets('Config List renders items and allows selection', (tester) async {
       tester.view.physicalSize = const Size(2400, 6000);
       tester.view.devicePixelRatio = 3.0;
       addTearDown(() => tester.view.resetPhysicalSize());

       final config1 = VpnConfigWithMetrics(id: 'c1', rawConfig: 'v1', name: 'Server 1', addedDate: DateTime.now());
       final config2 = VpnConfigWithMetrics(id: 'c2', rawConfig: 'v2', name: 'Server 2', addedDate: DateTime.now());

       when(() => mockConfigManager.allConfigs).thenReturn([config1, config2]);
       when(() => mockConfigManager.validatedConfigs).thenReturn([config1, config2]);
       when(() => mockConfigManager.favoriteConfigs).thenReturn([]);
       when(() => mockConfigManager.selectedConfig).thenReturn(config1);

       await tester.pumpWidget(createWidget());
       await tester.pumpAndSettle();

       expect(find.text('Server 1'), findsNWidgets(2));
       expect(find.text('Server 2'), findsOneWidget);

       await tester.tap(find.text('Server 2'));
       await tester.pumpAndSettle();

       verify(() => mockConfigManager.selectConfig(config2)).called(1);
    });

    testWidgets('Auto-Test Toggle updates state', (tester) async {
       await tester.pumpWidget(createWidget());
       await tester.pumpAndSettle();

       final switchFinder = find.byType(SwitchListTile);
       expect(switchFinder, findsOneWidget);

       final switchWidget = tester.widget<Switch>(find.byType(Switch));
       expect(switchWidget.value, true);

       await tester.tap(switchFinder);
       await tester.pumpAndSettle();

       final switchWidgetAfter = tester.widget<Switch>(find.byType(Switch));
       expect(switchWidgetAfter.value, false);
    });

    // --- NEW ITERATION 2 TESTS ---

    testWidgets('Scenario: No Access Alert blocks connection (Negative Assertion)', (tester) async {
       // Setup: No Access
       when(() => mockAccessManager.hasAccess).thenReturn(false);
       when(() => mockAccessManager.remainingTime).thenReturn(Duration.zero);

       // Setup: Valid Config exists
       final config = VpnConfigWithMetrics(id: 'c1', rawConfig: 'v1', name: 'Server 1', addedDate: DateTime.now());
       when(() => mockConfigManager.allConfigs).thenReturn([config]);
       when(() => mockConfigManager.validatedConfigs).thenReturn([config]);
       when(() => mockConfigManager.connectWithSmartFailover()).thenAnswer((_) async {});

       await tester.pumpWidget(createWidget());
       await tester.pumpAndSettle();

       // Tap Connect
       await tester.tap(find.text('CONNECT'));
       await tester.pumpAndSettle();

       // Verify "Add 1 Hour Time" Dialog appears
       expect(find.text('Add 1 Hour Time'), findsOneWidget);
       expect(find.textContaining('To keep the service free'), findsOneWidget);

       // Tap Cancel to close dialog without adding time
       await tester.tap(find.text('Cancel'));
       await tester.pumpAndSettle();

       // CRITICAL: Verify Connect Logic NEVER called
       verifyNever(() => mockConfigManager.connectWithSmartFailover());
    });

    testWidgets('Scenario: Reward Update flow adds time and updates UI', (tester) async {
       // Setup: No Access initially
       when(() => mockAccessManager.hasAccess).thenReturn(false);
       when(() => mockAccessManager.remainingTime).thenReturn(Duration.zero);

       // Setup: Ad Success Logic
       // When showPreConnectionAd is called, return true (Ad Watched)
       when(() => mockAdManagerService.showPreConnectionAd(any())).thenAnswer((_) async => true);

       // When addTime is called, update mock state and notify listeners
       when(() => mockAccessManager.addTime(any())).thenAnswer((invocation) async {
          when(() => mockAccessManager.hasAccess).thenReturn(true);
          when(() => mockAccessManager.remainingTime).thenReturn(const Duration(hours: 1));
          for (final l in accessListeners) {
            l();
          }
       });

       // Setup: Config
       final config = VpnConfigWithMetrics(id: 'c1', rawConfig: 'v1', name: 'Server 1', addedDate: DateTime.now());
       when(() => mockConfigManager.allConfigs).thenReturn([config]);
       when(() => mockConfigManager.validatedConfigs).thenReturn([config]);
       when(() => mockConfigManager.connectWithSmartFailover()).thenAnswer((_) async {});

       await tester.pumpWidget(createWidget());
       await tester.pumpAndSettle();

       // Verify initial state
       expect(find.text('No active plan'), findsOneWidget);

       // Tap Connect
       await tester.tap(find.text('CONNECT'));
       await tester.pumpAndSettle();

       // 1. "Add 1 Hour Time" Dialog -> Tap "View Ad"
       await tester.tap(find.text('View Ad'));
       await tester.pumpAndSettle();

       // Verify showPreConnectionAd called
       verify(() => mockAdManagerService.showPreConnectionAd(any())).called(1);

       // 2. "Claim Reward" Dialog -> Tap "Claim +1 Hour"
       expect(find.text('Claim Reward'), findsOneWidget);
       await tester.tap(find.text('Claim +1 Hour'));
       await tester.pumpAndSettle(); // Triggers addTime -> listener -> setState

       // Verify addTime called
       verify(() => mockAccessManager.addTime(const Duration(hours: 1))).called(1);

       // Verify UI Update (Reactivity Check)
       expect(find.text('1h 0m remaining'), findsOneWidget);
    });
  });
}
