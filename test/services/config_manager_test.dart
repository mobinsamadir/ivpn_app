import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:ivpn_new/services/native_vpn_service.dart';
import 'package:ivpn_new/services/testers/ephemeral_tester.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';

// Mocks
class MockNativeVpnService extends Mock implements NativeVpnService {}
class MockEphemeralTester extends Mock implements EphemeralTester {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigManager manager;
  late MockNativeVpnService mockNativeService;
  late MockEphemeralTester mockTester;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    // Create new mocks for each test
    mockNativeService = MockNativeVpnService();
    mockTester = MockEphemeralTester();

    // Get singleton instance
    manager = ConfigManager();
    await manager.clearAllData();
    manager.stopAllOperations(); // Reset kill switch

    // Inject mocks
    manager.setDependencies(vpnService: mockNativeService, tester: mockTester);

    // Register fallback values for verify
    registerFallbackValue(VpnConfigWithMetrics(
      id: 'fallback',
      rawConfig: 'vless://fallback',
      name: 'Fallback',
      addedDate: DateTime.now()
    ));
    registerFallbackValue(TestMode.connectivity);
  });

  group('ConfigManager Core Logic Shield', () {

    test('Scenario 1: Smart Failover Resilience - Fails twice, succeeds on third', () async {
      // Setup: Add 3 configs with decreasing timestamps so c1 is picked first (Sort: Date Descending)
      final now = DateTime.now();
      final c1 = VpnConfigWithMetrics(id: 'c1', rawConfig: 'vless://c1', name: 'Config 1', addedDate: now.add(const Duration(minutes: 3)), funnelStage: 2);
      final c2 = VpnConfigWithMetrics(id: 'c2', rawConfig: 'vless://c2', name: 'Config 2', addedDate: now.add(const Duration(minutes: 2)), funnelStage: 2);
      final c3 = VpnConfigWithMetrics(id: 'c3', rawConfig: 'vless://c3', name: 'Config 3', addedDate: now.add(const Duration(minutes: 1)), funnelStage: 2);

      // Populate lists
      manager.allConfigs.addAll([c1, c2, c3]);
      // Trigger update to sort and populate validatedConfigs
      await manager.updateConfigDirectly(c1);

      // Wait for async update/sort
      await Future.delayed(const Duration(milliseconds: 600));

      // Mock behavior using dynamic answer to avoid strict ordering issues in 'when' setup
      when(() => mockTester.runTest(any(), mode: any(named: 'mode')))
        .thenAnswer((invocation) async {
           final config = invocation.positionalArguments[0] as VpnConfigWithMetrics;
           if (config.id == 'c1') return c1.copyWith(funnelStage: 0, ping: -1);
           if (config.id == 'c2') return c2.copyWith(funnelStage: 0, ping: -1);
           if (config.id == 'c3') return c3.copyWith(funnelStage: 2, ping: 100);
           return config;
        });

      // Native Connect Success for c3
      when(() => mockNativeService.connect(c3.rawConfig)).thenAnswer((_) async {});

      // Execute
      await manager.connectWithSmartFailover();

      // Verify
      verify(() => mockTester.runTest(any(that: predicate((c) => (c as VpnConfigWithMetrics).id == 'c1')), mode: any(named: 'mode'))).called(1);
      verify(() => mockTester.runTest(any(that: predicate((c) => (c as VpnConfigWithMetrics).id == 'c2')), mode: any(named: 'mode'))).called(1);
      verify(() => mockTester.runTest(any(that: predicate((c) => (c as VpnConfigWithMetrics).id == 'c3')), mode: any(named: 'mode'))).called(1);

      verify(() => mockNativeService.connect(c3.rawConfig)).called(1);
    });

    test('Scenario 2: Total Blackout - All configs fail', () async {
      final c1 = VpnConfigWithMetrics(id: 'c1', rawConfig: 'vless://c1', name: 'Config 1', addedDate: DateTime.now(), funnelStage: 2);
      manager.allConfigs.add(c1);
      await manager.updateConfigDirectly(c1);
      await Future.delayed(const Duration(milliseconds: 600));

      // Fail
      when(() => mockTester.runTest(any(), mode: any(named: 'mode')))
          .thenAnswer((invocation) async {
             final c = invocation.positionalArguments[0] as VpnConfigWithMetrics;
             return c.copyWith(funnelStage: 0, ping: -1);
          });

      await manager.connectWithSmartFailover();

      verify(() => mockTester.runTest(any(), mode: any(named: 'mode'))).called(greaterThanOrEqualTo(1));
      verifyNever(() => mockNativeService.connect(any()));
      expect(manager.connectionStatus, contains('Failed'));
    });

    test('Scenario 3: Atomic Cancellation - Stop immediately', () async {
      final c1 = VpnConfigWithMetrics(id: 'c1', rawConfig: 'vless://c1', name: 'Config 1', addedDate: DateTime.now(), funnelStage: 2);
      manager.allConfigs.add(c1);
      await manager.updateConfigDirectly(c1);
      await Future.delayed(const Duration(milliseconds: 600));

      // Mock tester to delay so we can cancel
      when(() => mockTester.runTest(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async {
            await Future.delayed(const Duration(milliseconds: 200));
            return c1.copyWith(funnelStage: 2, ping: 100);
          });

      // Start connection
      final connectFuture = manager.connectWithSmartFailover();

      // Stop immediately
      await manager.stopAllOperations();

      // Wait for it to finish
      await connectFuture;

      // Verify
      // It should NOT call nativeService.connect because we stopped.
      verifyNever(() => mockNativeService.connect(any()));
      expect(manager.isGlobalStopRequested, isTrue);
    });
  });
}
