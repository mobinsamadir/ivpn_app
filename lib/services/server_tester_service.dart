import 'dart:async';
import 'dart:io';
import '../models/vpn_config_with_metrics.dart';
import '../services/config_manager.dart';
import '../services/latency_service.dart';
import '../services/windows_vpn_service.dart';
import '../utils/advanced_logger.dart';
import '../utils/cancellable_operation.dart';

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

  // Stream controller to emit updates for UI
  final _pipelineController = StreamController<VpnConfigWithMetrics>.broadcast();
  Stream<VpnConfigWithMetrics> get pipelineStream => _pipelineController.stream;

  ServerTesterService(WindowsVpnService vpnService)
      : _latencyService = LatencyService(vpnService),
        _configManager = ConfigManager() {
     // Bind to ConfigManager to allow triggering from other parts
     _configManager.onTriggerFunnel = () async => await startFunnel(autoConnect: true);
  }

  /// 3-Stage Funnel Testing Architecture
  Future<void> startFunnel({bool autoConnect = false}) async {
    final cancelToken = _configManager.getScanCancelToken();
    AdvancedLogger.info('[ServerTesterService] Starting Funnel Test (AutoConnect: $autoConnect)');

    // Initial Candidates
    List<VpnConfigWithMetrics> candidates = List.from(_configManager.allConfigs);

    // --- STAGE 1: TCP Filter (Availability) ---
    // Goal: Eliminate dead servers instantly
    // Concurrency: 20, Timeout: 1s
    AdvancedLogger.info('--- STAGE 1: TCP Filter (${candidates.length} configs) ---');
    final stage1Results = await _runStage(
      candidates,
      concurrency: 20,
      cancelToken: cancelToken,
      task: (c) async {
         final details = _extractServerDetails(c.rawConfig);
         if (details == null) return null;

         final latency = await _tcpPing(details['host'], details['port'], timeout: const Duration(seconds: 1));
         if (latency == -1) return null; // Fail

         return c.copyWith(
            lastTestedAt: DateTime.now(),
            stageResults: {...c.stageResults, 'Stage1': TestResult(success: true, latency: latency)}
         ).updateMetrics(deviceId: "local", ping: latency);
      }
    );

    if (cancelToken.isCancelled) return;

    // Filter & Sort for Stage 2
    // Take Top 20% (min 5)
    stage1Results.sort((a, b) => (a.currentPing).compareTo(b.currentPing));

    int stage2Count = (stage1Results.length * 0.2).ceil();
    if (stage2Count < 5 && stage1Results.length >= 5) stage2Count = 5;
    if (stage2Count > stage1Results.length) stage2Count = stage1Results.length;

    final stage2Candidates = stage1Results.take(stage2Count).toList();
    AdvancedLogger.info('--- STAGE 2: HTTP Latency (${stage2Candidates.length} configs) ---');

    // --- STAGE 2: HTTP Head (Real Latency) ---
    // Goal: Real delay measurement (Proxy Latency)
    // Concurrency: 5 (Strict limit for Windows), Timeout: 2s
    final stage2Results = await _runStage(
      stage2Candidates,
      concurrency: 5,
      cancelToken: cancelToken,
      task: (c) async {
         final result = await _latencyService.getAdvancedLatency(
            c.rawConfig,
            timeout: const Duration(seconds: 2)
         );

         if (result.health.averageLatency > 0) {
            return c.copyWith(
               stageResults: {...c.stageResults, 'Stage2': TestResult(success: true, latency: result.health.averageLatency)},
               isAlive: true,
            ).updateMetrics(deviceId: "local", ping: result.health.averageLatency, connectionSuccess: true);
         }
         return null; // Fail
      }
    );

    if (cancelToken.isCancelled) return;

    // Filter & Sort for Stage 3
    // Take Top 5 for heavy download test
    stage2Results.sort((a, b) => a.currentPing.compareTo(b.currentPing));
    final stage3Candidates = stage2Results.take(5).toList();

    AdvancedLogger.info('--- STAGE 3: Quality/Speed (${stage3Candidates.length} configs) ---');

    // --- STAGE 3: Download Test (Quality) ---
    // Goal: Speed & Stability
    // Concurrency: 1 (Sequential), 1MB File
    final finalResults = await _runStage(
       stage3Candidates,
       concurrency: 1,
       cancelToken: cancelToken,
       task: (c) async {
          final speed = await _latencyService.getDownloadSpeed(c.rawConfig); // Returns Mbps

          return c.copyWith(
             stageResults: {...c.stageResults, 'Stage3': TestResult(success: true, latency: 0)},
             tier: 3
          ).updateMetrics(deviceId: "local", speed: speed);
       }
    );

    // Scoring Formula: Score = (10000 / Latency) + (DownloadSpeed * 5)
    finalResults.sort((a, b) {
       final scoreA = (10000 / (a.currentPing > 0 ? a.currentPing : 9999)) + (a.currentSpeed * 5);
       final scoreB = (10000 / (b.currentPing > 0 ? b.currentPing : 9999)) + (b.currentSpeed * 5);
       return scoreB.compareTo(scoreA); // Descending
    });

    if (cancelToken.isCancelled) return;

    // Update ConfigManager
    _configManager.reserveList = finalResults;
    AdvancedLogger.info('Funnel Complete. Reserve List: ${finalResults.length}');

    // Auto Connect
    if (autoConnect && finalResults.isNotEmpty) {
       AdvancedLogger.info('Auto-connecting to winner: ${finalResults.first.name}');
       _configManager.selectConfig(finalResults.first);
       _configManager.onAutoSwitch?.call(finalResults.first);
    }
  }

  // Generic Batch Runner with Semaphore
  Future<List<VpnConfigWithMetrics>> _runStage({
    required List<VpnConfigWithMetrics> input,
    required int concurrency,
    required CancelToken cancelToken,
    required Future<VpnConfigWithMetrics?> Function(VpnConfigWithMetrics) task
  }) async {
      final results = <VpnConfigWithMetrics>[];
      final semaphore = Semaphore(concurrency);
      final futures = <Future<void>>[];

      for (final config in input) {
         if (cancelToken.isCancelled) break;

         final f =  () async {
            await semaphore.acquire();
            try {
               if (cancelToken.isCancelled) return;
               final res = await task(config);
               if (res != null) {
                  results.add(res);
                  _configManager.updateConfigDirectly(res); // Update UI
                  _pipelineController.add(res);
               }
            } catch (e) {
               // Log error
            } finally {
               semaphore.release();
            }
         }();
         futures.add(f);
      }

      await Future.wait(futures);
      return results;
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
