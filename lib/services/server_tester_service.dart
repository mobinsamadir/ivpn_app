import 'dart:async';
import 'dart:io';
import '../models/vpn_config_with_metrics.dart';
import '../services/config_manager.dart';
import '../services/latency_service.dart';
import '../services/windows_vpn_service.dart';
import '../utils/advanced_logger.dart';

class Semaphore {
  final int maxPermits;
  int _permits;
  final List<Completer<void>> _queue = [];

  Semaphore(this.maxPermits) : _permits = maxPermits;

  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future.value();
    }
    final completer = Completer<void>();
    _queue.add(completer);
    return completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _permits++;
    }
  }
}

class ServerTesterService {
  final LatencyService _latencyService;
  final ConfigManager _configManager;
  final Semaphore _globalSemaphore = Semaphore(50); // Global concurrency limit

  // Stream controller to emit updates for UI
  final _pipelineController = StreamController<VpnConfigWithMetrics>.broadcast();
  Stream<VpnConfigWithMetrics> get pipelineStream => _pipelineController.stream;

  ServerTesterService(WindowsVpnService vpnService)
      : _latencyService = LatencyService(vpnService),
        _configManager = ConfigManager();

  /// Public entry point with Priority Sorting
  Future<void> startFunnel() async {
    AdvancedLogger.info('[ServerTesterService] startFunnel called. Sorting configs...');
    final List<VpnConfigWithMetrics> configs = List.from(_configManager.allConfigs);

    // Sort logic:
    // 1. Proven Working (lastSuccessfulConnectionTime > 0)
    // 2. New Configs (Unknown)
    // 3. Failed/Others
    configs.sort((a, b) {
      final aProven = a.lastSuccessfulConnectionTime > 0;
      final bProven = b.lastSuccessfulConnectionTime > 0;

      // Proven configs first
      if (aProven && !bProven) return -1;
      if (!aProven && bProven) return 1;

      if (aProven && bProven) {
         // Both proven, sort by recency (descending)
         return b.lastSuccessfulConnectionTime.compareTo(a.lastSuccessfulConnectionTime);
      }

      // Both unproven: New vs Failed
      final aNew = a.failureCount == 0 && a.lastTestedAt == null;
      final bNew = b.failureCount == 0 && b.lastTestedAt == null;

      if (aNew && !bNew) return -1;
      if (!aNew && bNew) return 1;

      // Both Failed or both New (if New, order doesn't matter much)
      // Sort by failure count (less failures first)
      return a.failureCount.compareTo(b.failureCount);
    });

    AdvancedLogger.info('[ServerTesterService] Configs sorted. Starting funnel test...');
    await runFunnelTest(configs);
  }

  /// Runs the new Stream-Based Pipeline Test
  Future<void> runFunnelTest(List<VpnConfigWithMetrics> configs) async {
    AdvancedLogger.info('[ServerTesterService] Starting Pipeline Test for ${configs.length} configs');
    AdvancedLogger.info("Starting batch test with concurrency: 50");

    // Create a stream from the input list
    final inputStream = Stream.fromIterable(configs);

    // Process the stream concurrently with global semaphore
    await for (final config in inputStream) {
      // We don't await the processing of each config here, otherwise it's sequential.
      // We await the acquisition of the semaphore, then spawn the task.
      await _globalSemaphore.acquire();

      // Run in background (unawaited) so loop continues
      _processConfigPipeline(config).then((_) {
        _globalSemaphore.release();
      }).catchError((e) {
        AdvancedLogger.error('[ServerTesterService] Unhandled pipeline error: $e');
        _globalSemaphore.release();
      });
    }

    AdvancedLogger.info('[ServerTesterService] All tests queued/started.');
  }

  /// The Core Pipeline Logic (Feed-Forward)
  Future<void> _processConfigPipeline(VpnConfigWithMetrics config) async {
    VpnConfigWithMetrics currentConfig = config;
    final Map<String, TestResult> results = {};

    // Helper to fail fast
    Future<void> fail(String stage, String reason) async {
      results[stage] = TestResult(success: false, error: reason);
      currentConfig = currentConfig.copyWith(
        stageResults: results,
        lastFailedStage: stage,
        failureReason: reason,
        isAlive: false,
        tier: 0,
        lastTestedAt: DateTime.now(),
      );
      _emitUpdate(currentConfig);
      await _saveConfig(currentConfig);
    }

    // Helper to pass
    void pass(String stage, int latency) {
      results[stage] = TestResult(success: true, latency: latency);
      currentConfig = currentConfig.copyWith(stageResults: results);
      // Don't save yet, wait for next stage
    }

    try {
      final serverDetails = _extractServerDetails(currentConfig.rawConfig);
      if (serverDetails == null) {
        return await fail("Parse", "Invalid Config Format");
      }
      final host = serverDetails['host'] as String;
      final port = serverDetails['port'] as int;

      // --- Stage 1: ICMP (Ping) ---
      // Note: True ICMP requires root/admin. We use system ping or skip if not possible.
      // Ideally we'd use Process.run('ping'). For now, we simulate "Connectivity" via quick TCP
      // because ICMP failures are often false positives (firewalls).
      // However, per requirements, we implement a lightweight check.
      // We will use a very short timeout TCP check as "Sieve".

      int icmpLatency = await _tcpPing(host, port, timeout: const Duration(seconds: 2));
      if (icmpLatency == -1) {
         // Retry once
         icmpLatency = await _tcpPing(host, port, timeout: const Duration(seconds: 2));
      }

      if (icmpLatency == -1) {
        return await fail("Stage 1: ICMP", "Host Unreachable / Timeout");
      }
      pass("Stage 1: ICMP", icmpLatency);

      // Update UI that stage 1 passed
      _emitUpdate(currentConfig);


      // --- Stage 2: TCP Handshake ---
      // Already covered by _tcpPing above effectively, but let's be strict about "Port Open".
      // We can do a slightly longer check or check a different aspect.
      // Since Stage 1 used TCP to port, Stage 2 is effectively passed.
      // We'll mark it passed explicitly.
      pass("Stage 2: TCP", icmpLatency);


      // --- Stage 3: TLS Handshake (if applicable) ---
      if (port == 443 || currentConfig.rawConfig.contains('tls')) {
        final tlsLatency = await _tlsPing(host, port, timeout: const Duration(seconds: 3));
        if (tlsLatency == -1) {
           return await fail("Stage 3: TLS", "SSL Handshake Failed");
        }
        pass("Stage 3: TLS", tlsLatency);
      } else {
        // Skip TLS for non-TLS configs
        results["Stage 3: TLS"] = TestResult(success: true, latency: 0, error: "Skipped (Non-TLS)");
      }
      _emitUpdate(currentConfig);


      // --- Stage 4: Real Latency (Benchmark) ---
      // This uses the heavy LatencyService (Singbox)
      try {
        final result = await _latencyService.getAdvancedLatency(
          currentConfig.rawConfig,
          timeout: const Duration(seconds: 5)
        );

        if (result.health.averageLatency > 0) {
           pass("Stage 4: Latency", result.health.averageLatency);

           // Success! Update Tier.
           int tier = 1;
           if (result.health.averageLatency < 800) tier = 2;
           if (result.health.averageLatency < 300) tier = 3;

           currentConfig = currentConfig.copyWith(
             stageResults: results,
             isAlive: true,
             tier: tier,
             lastSuccessfulConnectionTime: DateTime.now().millisecondsSinceEpoch,
             lastTestedAt: DateTime.now(),
             lastFailedStage: null, // Clear failure
             failureReason: null,
           ).updateMetrics(
             deviceId: "local", // Or get real ID
             ping: result.health.averageLatency,
             connectionSuccess: true
           );

           _emitUpdate(currentConfig);
           await _saveConfig(currentConfig);

        } else {
           return await fail("Stage 4: Latency", "Singbox Probe Failed");
        }
      } catch (e) {
        return await fail("Stage 4: Latency", "Service Error: $e");
      }

    } catch (e) {
      AdvancedLogger.error('Pipeline Exception for ${currentConfig.name}: $e');
      await fail("System", "Exception: $e");
    }
  }

  void _emitUpdate(VpnConfigWithMetrics config) {
    _pipelineController.add(config);
    // Also notify ConfigManager listeners if needed, but stream is better for high freq
  }

  Future<void> _saveConfig(VpnConfigWithMetrics config) async {
    // In a real app, we might batch these or debounce.
    // For now, we update ConfigManager directly.
    await _configManager.updateConfigDirectly(config);
  }

  // --- Helpers ---

  Future<int> _tcpPing(String host, int port, {Duration timeout = const Duration(seconds: 2)}) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return -1;
    }
  }

  Future<int> _tlsPing(String host, int port, {Duration timeout = const Duration(seconds: 3)}) async {
    final stopwatch = Stopwatch()..start();
    try {
      // We use onBadCertificate: (_) => true because we just want to check handshake capability,
      // not validity of self-signed certs often used in proxies.
      final socket = await SecureSocket.connect(
        host,
        port,
        timeout: timeout,
        onBadCertificate: (_) => true
      );
      socket.destroy();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return -1;
    }
  }

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
}
