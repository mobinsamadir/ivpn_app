import 'dart:io';

void main() {
  // 1. FunnelService
  final funnelFile = File('lib/services/funnel_service.dart');
  String funnelContent = funnelFile.readAsStringSync();
  funnelContent = funnelContent.replaceFirst(
    '''  for (final c in allConfigs) {
    if (c.isFavorite) {''',
    '''  final now = DateTime.now();

  for (final c in allConfigs) {
    // Constraint 1: Time-Bound Smart Caching (TTL Logic)
    // If we are auto-running (retestDead = false) and the config was tested < 2 hours ago, skip entirely.
    if (!retestDead && c.lastTestedAt != null) {
      final hoursSinceTested = now.difference(c.lastTestedAt!).inHours;
      if (hoursSinceTested < 2) {
        continue;
      }
    }

    if (c.isFavorite) {'''
  );
  funnelContent = funnelContent.replaceFirst('int _speedFinished = 0;', 'int _speedFinished = 0;\n  int _totalFailed = 0;');
  funnelContent = funnelContent.replaceFirst('    _speedFinished = 0;', '    _speedFinished = 0;\n    _totalFailed = 0;');
  funnelContent = funnelContent.replaceFirst(
    '''    _progressController.add("Stopped");
    AdvancedLogger.info("FunnelService: Stopped by user.");
  }''',
    '''    _progressController.add("Stopped");
    AdvancedLogger.info("FunnelService: Stopped by user.");
    _printTelemetrySummary();
  }'''
  );
  funnelContent = funnelContent.replaceFirst(
    '''            stop();
            _progressController.add("Completed");
          }''',
    '''            stop();
            _progressController.add("Completed");
            _printTelemetrySummary();
          }'''
  );
  if (!funnelContent.contains("import 'package:flutter/foundation.dart';")) {
     funnelContent = "import 'package:flutter/foundation.dart';\n" + funnelContent;
  }
  funnelContent = funnelContent.replaceFirst(
    '''  void _startUiThrottle() {''',
    '''  void _printTelemetrySummary() {
    debugPrint("--- [TELEMETRY] FUNNEL RUN SUMMARY ---");
    debugPrint("Total Tested: \$_totalConfigs");
    debugPrint("Total Passed TCP: \$_tcpPassed");
    debugPrint("Total Passed HTTP: \$_httpPassed");
    debugPrint("Total Passed Speed: \$_speedFinished");
    debugPrint("Total Failed: \$_totalFailed");
    debugPrint("--------------------------------------");
  }

  void _startUiThrottle() {'''
  );
  funnelContent = funnelContent.replaceFirst(
    '''          // Failed TCP - Mark Dead
          await _configManager.markFailure(config.id);
        }
      } catch (e) {
        AdvancedLogger.warn("TCP Worker Error: \$e");
      } finally {''',
    '''          // Failed TCP - Mark Dead
          _totalFailed++;
          debugPrint("[TELEMETRY] \${config.name} | LastPassedStage: 0 | PingDuration: N/A | ExactException: TCP Connect Timeout");
          await _configManager.markFailure(config.id);
        }
      } catch (e) {
        _totalFailed++;
        debugPrint("[TELEMETRY] \${config?.name ?? 'Unknown'} | LastPassedStage: 0 | PingDuration: N/A | ExactException: \$e");
        AdvancedLogger.warn("TCP Worker Error: \$e");
      } finally {'''
  );
  funnelContent = funnelContent.replaceFirst(
    '''        if (result.funnelStage >= 2) {
          // Success (2 or 3)
          _httpPassed++;

          // Update Manager (triggers Sort & UI update)
          await _configManager.updateConfigDirectly(result);

          // Promote to Speed Queue
          _speedQueue.add(result);
        } else {
          await _configManager.markFailure(config.id);
        }
      } catch (e) {
        AdvancedLogger.warn("HTTP Worker Error: \$e");
      } finally {''',
    '''        if (result.funnelStage >= 2) {
          // Success (2 or 3)
          _httpPassed++;
          debugPrint("[TELEMETRY] \${config.name} | LastPassedStage: 2 | PingDuration: \${result.currentPing} | ExactException: None");

          // Update Manager (triggers Sort & UI update)
          await _configManager.updateConfigDirectly(result);

          // Promote to Speed Queue
          _speedQueue.add(result);
        } else {
          _totalFailed++;
          debugPrint("[TELEMETRY] \${config.name} | LastPassedStage: 1 | PingDuration: \${result.currentPing} | ExactException: HTTP Failed (No 204)");
          await _configManager.markFailure(config.id);
        }
      } catch (e) {
        _totalFailed++;
        debugPrint("[TELEMETRY] \${config?.name ?? 'Unknown'} | LastPassedStage: 1 | PingDuration: N/A | ExactException: \$e");
        AdvancedLogger.warn("HTTP Worker Error: \$e");
      } finally {'''
  );
  funnelFile.writeAsStringSync(funnelContent);

  // 2. ConfigManager
  final configManagerFile = File('lib/services/config_manager.dart');
  String configManagerContent = configManagerFile.readAsStringSync();
  configManagerContent = configManagerContent.replaceFirst(
    '''  // Aliases for compatibility
  Future<void> addConfig(String raw, String name) => addConfigs([raw]);''',
    '''  // --- MANUAL FORCED CONNECTION ---
  Future<void> connectManual(VpnConfigWithMetrics target) async {
    userInitiatedDisconnect = false;
    isConnectionCancelled = false;
    _isGlobalStopRequested = false;

    AdvancedLogger.info(
        '[ConfigManager] Starting Manual Connection to \${target.name}...');
    setConnected(false, status: 'Connecting...');
    selectConfig(target);

    final NativeVpnService nativeService = NativeVpnService();

    try {
      // Initiate native connection
      await nativeService.connect(target.rawConfig);

      // Wait for CONNECTED state with strict 10-second timeout
      await nativeService.connectionStatusStream
          .firstWhere((status) => status == 'CONNECTED')
          .timeout(const Duration(seconds: 10));

      AdvancedLogger.info(
          '[ConfigManager] Manual Connection Success: \${target.name}');
      // Optional: nativeService emits 'CONNECTED' and UI will catch it via stream listener.
      // But we can ensure state is updated.
      // Do not call setConnected(true) here if NativeVpnService handles broadcasting it to main UI,
      // but if we rely on it, wait for stream is sufficient.
    } catch (e) {
      AdvancedLogger.warn('[ConfigManager] Manual Connection Failed: \$e');

      // Force native disconnect immediately
      await nativeService.disconnect();

      // Notify UI of failure so it can show the red banner
      setConnected(false, status: 'Connection Failed');

      // Throw exception so caller can also catch if needed
      throw Exception("Manual connection failed: \$e");
    }
  }

  // Aliases for compatibility
  Future<void> addConfig(String raw, String name) => addConfigs([raw]);'''
  );
  configManagerFile.writeAsStringSync(configManagerContent);

  // 3. EphemeralTester
  final testerFile = File('lib/services/testers/ephemeral_tester.dart');
  String testerContent = testerFile.readAsStringSync();
  testerContent = testerContent.replaceFirst(
    '''        final client = HttpClient();

        try {
          client.findProxy = (uri) => "SOCKS5 127.0.0.1:\$proxyPort";''',
    '''        final client = HttpClient();

        try {
          // Constraint 3: Isolated SSL Bypass
          client.badCertificateCallback = (cert, host, port) => true;

          client.findProxy = (uri) => "SOCKS5 127.0.0.1:\$proxyPort";'''
  );
  testerContent = testerContent.replaceFirst(
    '''      final dartHttpClient = HttpClient();

      bool stage1Success = false;''',
    '''      final dartHttpClient = HttpClient();
      // Constraint 3: Isolated SSL Bypass
      dartHttpClient.badCertificateCallback = (cert, host, port) => true;

      bool stage1Success = false;'''
  );
  testerFile.writeAsStringSync(testerContent);

  // 4. VpnConfigWithMetrics
  final modelFile = File('lib/models/vpn_config_with_metrics.dart');
  String modelContent = modelFile.readAsStringSync();
  modelContent = modelContent.replaceFirst(
    '''    if (deviceMetrics.isEmpty) return -1;
    return deviceMetrics.values.first.latestPing;''',
    '''    if (deviceMetrics.isEmpty) return -1;
    // Safely unwrap using ?. and ??
    return deviceMetrics.values.firstOrNull?.latestPing ?? -1;'''
  );
  modelContent = modelContent.replaceFirst(
    '''    if (deviceMetrics.isEmpty) return 0.0;
    return deviceMetrics.values.first.latestSpeed;''',
    '''    if (deviceMetrics.isEmpty) return 0.0;
    // Safely unwrap using ?. and ??
    return deviceMetrics.values.firstOrNull?.latestSpeed ?? 0.0;'''
  );
  modelFile.writeAsStringSync(modelContent);

  // 5. ConnectionHomeScreen
  final homeFile = File('lib/screens/connection_home_screen.dart');
  String homeContent = homeFile.readAsStringSync();
  homeContent = homeContent.replaceFirst(
    '''  bool _autoRefreshOnStartup = false;''',
    '''  bool _autoRefreshOnStartup = true;'''
  );
  homeContent = homeContent.replaceFirst(
    '''        _autoRefreshOnStartup = prefs.getBool('autoRefreshOnStartup') ?? false;''',
    '''        _autoRefreshOnStartup = prefs.getBool('autoRefreshOnStartup') ?? true;'''
  );
  homeContent = homeContent.replaceFirst(
    '''    if (_configManager.selectedConfig != null &&
        _configManager.selectedConfig!.currentPing > 3000) {''',
    '''    if (_configManager.selectedConfig != null &&
        (_configManager.selectedConfig?.currentPing ?? 0) > 3000) {'''
  );
  homeFile.writeAsStringSync(homeContent);
}
