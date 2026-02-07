import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/vpn_config_with_metrics.dart';
import '../services/config_manager.dart';
import '../services/latency_service.dart';
import '../services/windows_vpn_service.dart';
import '../utils/advanced_logger.dart';

class ServerTesterService {
  final LatencyService _latencyService;
  final ConfigManager _configManager;

  ServerTesterService(WindowsVpnService vpnService)
      : _latencyService = LatencyService(vpnService),
        _configManager = ConfigManager();

  /// Runs the 3-phase funnel test on a list of configs
  Future<void> runFunnelTest(List<VpnConfigWithMetrics> configs) async {
    AdvancedLogger.info('[ServerTesterService] Starting Funnel Test for ${configs.length} configs');

    // Phase 1: The Sieve - Quick TCP/HTTP Head check
    await _runSievePhase(configs);

    // Phase 2: The Benchmark - Detailed latency testing
    await _runBenchmarkPhase(configs);

    // Phase 3: The Stress Test - Stability/speed testing (top 5)
    await _runStressPhase(configs);

    AdvancedLogger.info('[ServerTesterService] Funnel Test completed');
  }

  /// Phase 1: Quick connectivity check on ALL configs concurrently (batch size 20, timeout 2s)
  Future<void> _runSievePhase(List<VpnConfigWithMetrics> configs) async {
    AdvancedLogger.info('[ServerTesterService] Phase 1: Sieve - Connectivity Check');

    // Process configs in batches of 20 with timeout
    for (int i = 0; i < configs.length; i += 20) {
      final endIndex = (i + 20 < configs.length) ? i + 20 : configs.length;
      final batch = configs.sublist(i, endIndex);

      // Run connectivity checks concurrently for this batch with timeout
      final futures = batch.map((config) async {
        try {
          final isAlive = await _quickConnectivityCheck(config).timeout(const Duration(seconds: 2));
          // Update config properties
          final updatedConfig = config.copyWith(
            isAlive: isAlive,
            tier: isAlive ? 1 : 0,
          );

          // Update in the original list
          final index = configs.indexOf(config);
          if (index != -1) {
            configs[index] = updatedConfig;
          }

          // Save to storage
          if (!isAlive) {
            await _configManager.updateConfigMetrics(config.id, connectionSuccess: false);
          }
        } catch (e) {
          AdvancedLogger.error('[ServerTesterService] Error in sieve phase for ${config.name}: $e');
          // Mark as dead on error or timeout
          final index = configs.indexOf(config);
          if (index != -1) {
            configs[index] = config.copyWith(
              isAlive: false,
              tier: 0,
            );
          }
        }
      }).toList();

      await Future.wait(futures);
    }

    // Save all updates after Phase 1
    await _saveBatchUpdates(configs);
    AdvancedLogger.info('[ServerTesterService] Phase 1 completed');
  }

  /// Phase 2: Detailed latency testing on alive configs (batch size 5, timeout 5s)
  Future<void> _runBenchmarkPhase(List<VpnConfigWithMetrics> configs) async {
    AdvancedLogger.info('[ServerTesterService] Phase 2: Benchmark - Latency Testing');

    // Get only alive configs
    final aliveConfigs = configs.where((config) => config.isAlive).toList();
    if (aliveConfigs.isEmpty) {
      AdvancedLogger.info('[ServerTesterService] No alive configs to benchmark');
      return;
    }

    // Process alive configs in batches of 5 with timeout
    for (int i = 0; i < aliveConfigs.length; i += 5) {
      final endIndex = (i + 5 < aliveConfigs.length) ? i + 5 : aliveConfigs.length;
      final batch = aliveConfigs.sublist(i, endIndex);

      // Test latency concurrently for this batch with timeout
      final futures = batch.map((config) async {
        try {
          final result = await _latencyService.getAdvancedLatency(config.rawConfig)
              .timeout(const Duration(seconds: 5));
          final latency = result.health.averageLatency;

          // Update metrics
          await _configManager.updateConfigMetrics(
            config.id,
            ping: latency,
            connectionSuccess: latency > 0,
          );

          // Update tier based on latency (if low latency, promote to tier 2)
          final updatedTier = latency > 0 && latency < 500 ? 2 : 1;
          final index = configs.indexOf(config);
          if (index != -1) {
            configs[index] = config.copyWith(tier: updatedTier);
          }
        } catch (e) {
          AdvancedLogger.error('[ServerTesterService] Error in benchmark phase for ${config.name}: $e');
          final index = configs.indexOf(config);
          if (index != -1) {
            configs[index] = config.copyWith(
              isAlive: false,
              tier: 0,
            );
          }
        }
      }).toList();

      await Future.wait(futures);
    }

    // Sort alive configs by latency and promote top 50% to tier 2
    final sortedAlive = configs
        .where((config) => config.isAlive && config.tier >= 1)
        .toList()
        ..sort((a, b) => a.currentPing.compareTo(b.currentPing));

    final topHalfCount = (sortedAlive.length / 2).ceil();
    for (int i = 0; i < sortedAlive.length; i++) {
      final config = sortedAlive[i];
      final newTier = i < topHalfCount ? 2 : 1; // Top 50% get tier 2
      final index = configs.indexOf(config);
      if (index != -1) {
        configs[index] = config.copyWith(tier: newTier);
      }
    }

    // Save all updates after Phase 2
    await _saveBatchUpdates(configs);
    AdvancedLogger.info('[ServerTesterService] Phase 2 completed');
  }

  /// Phase 3: Stress test on top 5 configs
  Future<void> _runStressPhase(List<VpnConfigWithMetrics> configs) async {
    AdvancedLogger.info('[ServerTesterService] Phase 3: Stress Test - Stability/Speed');

    // Get top 5 configs by tier and score
    final topConfigs = configs
        .where((config) => config.tier >= 2)
        .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

    final configsToTest = topConfigs.length > 5 ? topConfigs.sublist(0, 5) : topConfigs;
    if (configsToTest.isEmpty) {
      AdvancedLogger.info('[ServerTesterService] No configs to stress test');
      return;
    }

    // Run stability test on each top config
    for (final config in configsToTest) {
      try {
        final result = await _latencyService.runStabilityTest(
          config.rawConfig,
          duration: Duration(seconds: 15), // Shorter stress test
        );

        // Update metrics
        await _configManager.updateConfigMetrics(
          config.id,
          ping: result.health.averageLatency,
          connectionSuccess: result.health.averageLatency > 0,
        );

        // Promote to tier 3 if stability is good
        final updatedTier = result.stability != null && result.stability!.packetLoss < 0.1 ? 3 : config.tier;
        final index = configs.indexOf(config);
        if (index != -1) {
          configs[index] = config.copyWith(tier: updatedTier);
        }
      } catch (e) {
        AdvancedLogger.error('[ServerTesterService] Error in stress phase for ${config.name}: $e');
        final index = configs.indexOf(config);
        if (index != -1) {
          configs[index] = config.copyWith(tier: config.tier); // Keep current tier on error
        }
      }
    }

    // Save all updates after Phase 3
    await _saveBatchUpdates(configs);
    AdvancedLogger.info('[ServerTesterService] Phase 3 completed');
  }

  /// Quick connectivity check using TCP ping and HTTP head request
  Future<bool> _quickConnectivityCheck(VpnConfigWithMetrics config) async {
    try {
      // Extract host and port from config
      final serverDetails = _extractServerDetails(config.rawConfig);
      if (serverDetails == null) return false;

      final host = serverDetails['host'] as String;
      final port = serverDetails['port'] as int;

      // TCP ping
      final socket = await Socket.connect(host, port, timeout: Duration(seconds: 5));
      socket.destroy();
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Extract server details from config URL
  Map<String, dynamic>? _extractServerDetails(String configUrl) {
    try {
      final uri = Uri.parse(configUrl);
      final protocol = uri.scheme;
      final host = uri.host;
      final port = uri.port != 0 ? uri.port : _getDefaultPort(protocol);
      
      return {'host': host, 'port': port};
    } catch (e) {
      return null;
    }
  }

  /// Get default port for protocol
  int _getDefaultPort(String protocol) {
    switch (protocol) {
      case 'vmess':
      case 'vless':
        return 443;
      case 'ss':
        return 8388;
      case 'trojan':
        return 443;
      default:
        return 80;
    }
  }

  /// Save batch updates to config manager
  Future<void> _saveBatchUpdates(List<VpnConfigWithMetrics> configs) async {
    // Just notify listeners since individual configs are updated during testing
    _configManager.notifyListeners();
  }
}