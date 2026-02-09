import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/vpn_config_with_metrics.dart';
import '../services/config_manager.dart';
import '../services/latency_service.dart';
import '../services/windows_vpn_service.dart';
import '../utils/advanced_logger.dart';

class ServerTesterService {
  final LatencyService _latencyService;
  final ConfigManager _configManager;

  ServerTesterService(WindowsVpnService vpnService, {LatencyService? latencyService, ConfigManager? configManager})
      : _latencyService = latencyService ?? LatencyService(vpnService),
        _configManager = configManager ?? ConfigManager();

  /// Runs the "Smart Cascade" pipeline on a list of configs
  Future<void> runFunnelTest(List<VpnConfigWithMetrics> configs) async {
    AdvancedLogger.info('[ServerTesterService] Starting Smart Cascade Test for ${configs.length} configs');

    // Reset best config candidate tracking
    _resetBestConfigTracking();

    // Start Hot-Swap Mode in ConfigManager
    _configManager.startHotSwap();

    // Stage 1: The Sieve (TCP + TLS)
    // We process survivors of Stage 1 immediately into Stage 2 & 3
    await _runCascadePipeline(configs);

    // Stop Hot-Swap Mode
    _configManager.stopHotSwap();

    AdvancedLogger.info('[ServerTesterService] Smart Cascade Test completed');
  }

  void _resetBestConfigTracking() {
    // Handled by ConfigManager.startHotSwap()
  }

  /// The Main Pipeline: Sieve -> Latency -> Stability
  Future<void> _runCascadePipeline(List<VpnConfigWithMetrics> allConfigs) async {
    // Process in batches to avoid resource exhaustion
    const int batchSize = 50;

    for (int i = 0; i < allConfigs.length; i += batchSize) {
      final endIndex = (i + batchSize < allConfigs.length) ? i + batchSize : allConfigs.length;
      final batch = allConfigs.sublist(i, endIndex);

      AdvancedLogger.info('[ServerTesterService] Processing batch ${i ~/ batchSize + 1} (${batch.length} configs)');

      // STAGE 1: The Sieve (TCP + Generic TLS)
      final sieveSurvivors = await _runSieveStage(batch);

      if (sieveSurvivors.isEmpty) {
        AdvancedLogger.info('[ServerTesterService] No survivors from Sieve in this batch.');
        continue;
      }

      // STAGE 2 & 3: Real Protocol Latency & Stability
      // We run these concurrently for the survivors of the batch
      await _runDeepAnalysisStages(sieveSurvivors);
    }
  }

  // --- STAGE 1: THE SIEVE ---
  Future<List<VpnConfigWithMetrics>> _runSieveStage(List<VpnConfigWithMetrics> batch) async {
    final List<VpnConfigWithMetrics> survivors = [];

    // Run concurrently
    final futures = batch.map((config) async {
      try {
        final isAlive = await _checkTcpAndTls(config);

        if (isAlive) {
          // Mark as alive (Tier 1)
          final updated = config.copyWith(
            isAlive: true,
            tier: 1,
            failureCount: 0 // Reset failure count on success
          );
          _configManager.updateConfigMetrics(updated.id, connectionSuccess: false); // Just update metadata
          survivors.add(updated);
        } else {
          // Mark as dead
          // _configManager.markFailure(config.id); // Optional: don't be too harsh on simple check failure?
        }
      } catch (e) {
        // Ignore errors in sieve
      }
    });

    await Future.wait(futures);
    return survivors;
  }

  Future<bool> _checkTcpAndTls(VpnConfigWithMetrics config) async {
    try {
      final details = _extractServerDetails(config.rawConfig);
      if (details == null) return false;

      final host = details['host'] as String;
      final port = details['port'] as int;
      final isTls = details['isTls'] as bool;

      // 1. TCP Connect (Timeout 2s)
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));

      // 2. Generic TLS Handshake (if applicable)
      if (isTls || port == 443) {
        try {
          final secureSocket = await SecureSocket.secure(
            socket,
            onBadCertificate: (_) => true, // We don't care about cert validity here, just handshake
            timeout: const Duration(seconds: 2)
          );
          secureSocket.destroy();
        } catch (e) {
          socket.destroy();
          return false; // TCP ok but TLS failed
        }
      } else {
        socket.destroy();
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  // --- STAGE 2 & 3: REAL LATENCY & STABILITY ---
  Future<void> _runDeepAnalysisStages(List<VpnConfigWithMetrics> survivors) async {
    // Run concurrently but limit concurrency for Sing-box instances
    const int maxConcurrency = 3;
    await _processWithPool(survivors, maxConcurrency, _processSingleDeepAnalysis);
  }

  // Helper to process list with limited concurrency (Simple FIFO throttle)
  Future<void> _processWithPool(
      List<VpnConfigWithMetrics> items,
      int poolSize,
      Future<void> Function(VpnConfigWithMetrics) processor
  ) async {
    final pool = <Future<void>>[];

    for (final item in items) {
      // Add new task
      pool.add(processor(item));

      // If pool is full, wait for the oldest task to complete (FIFO)
      // This is a simple throttling mechanism.
      // While suboptimal (head-of-line blocking), it limits concurrency effectively.
      if (pool.length >= poolSize) {
        await pool[0];
        pool.removeAt(0);
      }
    }

    // Wait for remaining tasks
    await Future.wait(pool);
  }

  Future<void> _processSingleDeepAnalysis(VpnConfigWithMetrics config) async {
     try {
       // STAGE 2: Real Protocol Latency
       // Use Sing-box to measure url-test to http://cp.cloudflare.com
       final result = await _latencyService.getAdvancedLatency(
         config.rawConfig,
         timeout: const Duration(seconds: 5), // Strict timeout
       );

       final latency = result.health.averageLatency;

       // DISCARD if delay > 3000ms or failed (-1)
       if (latency <= 0 || latency > 3000) {
          // Update as failed/high latency
          await _configManager.updateConfigMetrics(config.id, ping: latency > 0 ? latency.toInt() : -1, connectionSuccess: false);
          return;
       }

       // STAGE 3: Stability Check (Jitter)
       // Send 3 rapid pings (approx). We use runStabilityTest with short duration.
       // Duration 2s should give ~4 samples with default 500ms interval.
       final stabilityResult = await _latencyService.runStabilityTest(
         config.rawConfig,
         duration: const Duration(seconds: 2),
         timeout: const Duration(seconds: 5),
       );

       final jitter = stabilityResult.stability?.jitter ?? 0.0;
       final avgLatency = stabilityResult.health.averageLatency > 0
           ? stabilityResult.health.averageLatency
           : latency; // Fallback to stage 2 latency if stage 3 fails

       if (avgLatency <= 0) return; // Stage 3 failed completely

       // Calculate Priority Score: (Latency * 0.7) + (Jitter * 0.3)
       // Lower is better.
       // Note: config.score is "Higher is better". We need to handle this mapping.
       // The requirement defines the algorithm for *selection*.

       // Update Config with Metrics
       await _configManager.updateConfigMetrics(
         config.id,
         ping: avgLatency.toInt(),
         jitter: jitter,
         connectionSuccess: true
       );

       // Check for Hot-Swap
       final updatedConfig = _configManager.getConfigById(config.id);
       if (updatedConfig != null) {
          await _configManager.considerCandidate(updatedConfig);
       }

     } catch (e) {
       AdvancedLogger.warn('[ServerTester] Error processing ${config.name}: $e');
     }
  }

  // --- HELPERS ---
  Map<String, dynamic>? _extractServerDetails(String configUrl) {
    try {
      final uri = Uri.parse(configUrl);
      final protocol = uri.scheme;
      final host = uri.host;
      final port = uri.port != 0 ? uri.port : _getDefaultPort(protocol);
      
      // Heuristic for TLS
      bool isTls = false;
      if (protocol == 'trojan' || protocol == 'hysteria' || protocol == 'hysteria2' || protocol == 'tuic') {
        isTls = true;
      } else if (protocol == 'vmess' || protocol == 'vless') {
         // Check streamSettings or query params if possible (simplified here)
         if (uri.queryParameters['security'] == 'tls' || port == 443) isTls = true;
      }

      return {'host': host, 'port': port, 'isTls': isTls};
    } catch (e) {
      return null;
    }
  }

  int _getDefaultPort(String protocol) {
    switch (protocol) {
      case 'vmess':
      case 'vless':
      case 'trojan':
        return 443;
      case 'ss':
        return 8388;
      default:
        return 80;
    }
  }
}
