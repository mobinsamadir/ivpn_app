import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';
import 'package:mockito/mockito.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for tests or mock path provider
  setUpAll(() async {
    const MethodChannel('plugins.flutter.io/path_provider')
      .setMockMethodCallHandler((MethodCall methodCall) async {
      return '.';
    });
    
    Hive.init('.');
    Hive.registerAdapter(VpnConfigWithMetricsAdapter());
    Hive.registerAdapter(DeviceMetricsAdapter());
    Hive.registerAdapter(PingRecordAdapter());
    Hive.registerAdapter(SpeedRecordAdapter());
  });

  test('Hive serialization/deserialization works', () async {
    final boxName = 'test_box_${DateTime.now().millisecondsSinceEpoch}';
    final box = await Hive.openBox<VpnConfigWithMetrics>(boxName);
    
    // Create config with unnamed constructor mechanism implicitly used by Hive
    // But here we construct it normally to save
    final config = VpnConfigWithMetrics(
      id: 'test-id',
      rawConfig: 'test://config',
      name: 'Test Server',
      countryCode: 'US',
    );
    
    // Update some metrics
    config.updateMetrics(ping: 100, speed: 50.0);
    
    // Save to Hive
    await box.put('key1', config);
    
    // Load from Hive
    final loaded = box.get('key1');
    
    expect(loaded, isNotNull);
    expect(loaded!.id, 'test-id');
    expect(loaded.name, 'Test Server');
    expect(loaded.currentPing, 100);
    
    await box.close();
    // Cleanup handled by OS mostly for temp files, or we ignore
  });
}
