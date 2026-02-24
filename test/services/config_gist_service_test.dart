import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ivpn_new/services/config_gist_service.dart';
import 'package:ivpn_new/services/config_manager.dart';

class MockConfigManager extends Mock implements ConfigManager {}

// Minimal MockHttpOverrides just to simulate failure
class FailingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return FailingHttpClient();
  }
}

class FailingHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    throw const SocketException('Simulated network failure');
  }
}

void main() {
  late MockConfigManager mockManager;
  late ConfigGistService service;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    mockManager = MockConfigManager();
    service = ConfigGistService();

    // Mock ConfigManager behavior
    when(() => mockManager.allConfigs).thenReturn([]);
    // Ensure addConfigs returns a Future<int>
    when(() => mockManager.addConfigs(any(), checkBlacklist: any(named: 'checkBlacklist')))
        .thenAnswer((_) async => 1);
  });

  test('fetchAndApplyConfigs uses backup on network failure', () async {
    // 1. Setup Failing Network
    HttpOverrides.global = FailingHttpOverrides();

    // 2. Setup Backup in SharedPreferences
    final backupConfigs = ['vmess://backup1', 'vless://backup2'];
    SharedPreferences.setMockInitialValues({
      'gist_backup_configs': jsonEncode(backupConfigs),
      'last_config_fetch_timestamp': 0, // Ensure fetch triggers
    });

    // 3. Execute
    // We use force=true to bypass the time check and ensure fetch is attempted
    await service.fetchAndApplyConfigs(mockManager, force: true);

    // 4. Verify Backup Used
    // The loop tries mirrors, they fail. Then fail-safe block runs.
    final captured = verify(() => mockManager.addConfigs(captureAny(), checkBlacklist: true)).captured;

    expect(captured.length, 1);
    final appliedConfigs = captured.first as List<String>;
    expect(appliedConfigs, equals(backupConfigs));
  });

  tearDown(() {
    HttpOverrides.global = null; // Reset
  });
}
