import 'dart:async';
import 'dart:io';
import '../models/vpn_config_with_metrics.dart';
import 'config_manager.dart';
import 'singbox_config_generator.dart';
import 'testers/ephemeral_tester.dart';
import '../utils/advanced_logger.dart';
import '../utils/cancellable_operation.dart';
import 'native_vpn_service.dart';

class FunnelService {
  static final FunnelService _instance = FunnelService._internal();
  factory FunnelService() => _instance;
  FunnelService._internal();

  final ConfigManager _configManager = ConfigManager();
  final EphemeralTester _tester = EphemeralTester();

  // Queues
  final List<VpnConfigWithMetrics> _tcpQueue = [];
  final List<VpnConfigWithMetrics> _httpQueue = [];
  final List<VpnConfigWithMetrics> _speedQueue = [];

  // Active Worker Counts
  int _activeTcpWorkers = 0;
  int _activeHttpWorkers = 0;
  int _activeSpeedWorkers = 0;

  // Limits
  static const int _maxTcpWorkers = 20;
  static const int _maxHttpWorkers = 5;
  static const int _maxSpeedWorkers = 2;

  // State
  bool _isRunning = false;
  CancelToken? _cancelToken;

  // Stats
  int _totalConfigs = 0;
  int _tcpPassed = 0;
  int _httpPassed = 0;
  int _speedFinished = 0;

  // Progress Stream
  final _progressController = StreamController<String>.broadcast();
  Stream<String> get progressStream => _progressController.stream;

  Future<void> stop() async {
    _isRunning = false;
    _cancelToken?.cancel();
    _tcpQueue.clear();
    _httpQueue.clear();
    _speedQueue.clear();
    _progressController.add("Stopped");
    AdvancedLogger.info("FunnelService: Stopped by user.");
  }

  Future<void> startFunnel({bool retestDead = false}) async {
    if (_isRunning) {
      AdvancedLogger.warn("FunnelService: Already running.");
      return;
    }

    _isRunning = true;
    _cancelToken = CancelToken();
    _tcpPassed = 0;
    _httpPassed = 0;
    _speedFinished = 0;

    AdvancedLogger.info("FunnelService: Starting Pipeline (RetestDead: $retestDead)");

    // Android-specific parallel pipeline
    if (Platform.isAndroid) {
      // Don't await here so it runs in background like the original implementation
      _runAndroidFunnel(retestDead).ignore();
      return;
    }

    _progressController.add("Initializing Pipeline...");

    // 1. Populate TCP Queue (Initial Feed)
    final all = _buildPriorityQueue(retestDead);
    _totalConfigs = all.length;
    _tcpQueue.addAll(all);

    AdvancedLogger.info("FunnelService: Loaded ${_totalConfigs} configs into TCP Queue.");
    _progressController.add("Queue: $_totalConfigs configs");

    // 2. Start Worker Pools
    // Reduce TCP workers on Windows to prevent port exhaustion
    int tcpWorkers;
    if (Platform.isWindows) {
      tcpWorkers = 5;
    } else {
      tcpWorkers = 12; // Default for others (Linux/macOS)
    }
    await _spawnWorkers(tcpWorkers, _tcpWorker, "TCP");
    await _spawnWorkers(_maxHttpWorkers, _httpWorker, "HTTP");
    await _spawnWorkers(_maxSpeedWorkers, _speedWorker, "Speed");
  }

  // Optimized Android Pipeline using Native MethodChannel
  Future<void> _runAndroidFunnel(bool retestDead) async {
    _progressController.add("Android Pipeline: Initializing...");
    final all = _buildPriorityQueue(retestDead);
    _totalConfigs = all.length;
    final nativeService = NativeVpnService();
    AdvancedLogger.info("FunnelService (Android): Loaded $_totalConfigs configs.");

    // Batch processing
    const int batchSize = 4;
    for (int i = 0; i < all.length; i += batchSize) {
      if (!_isRunning || _cancelToken!.isCancelled) break;

      final batch = all.skip(i).take(batchSize).toList();
      _activeHttpWorkers = batch.length; // Reuse this counter for UI visibility
      _updateProgress();

      await Future.wait(batch.map((config) async {
        if (!_isRunning) return;
        try {
          final ping = await nativeService.getPing(config.rawConfig);
          if (ping > 0) {
            _httpPassed++;
            // Mark as valid (Stage 2 passed equivalent)
            final updated = config.copyWith(
              funnelStage: 2,
              ping: ping,
              lastTestedAt: DateTime.now(),
              failureCount: 0
            );
            await _configManager.updateConfigDirectly(updated);
          } else {
             await _configManager.markFailure(config.id);
          }
        } catch (e) {
          await _configManager.markFailure(config.id);
        }
      }));

      _activeHttpWorkers = 0;
      _updateProgress();
    }

    if (_isRunning) {
        stop();
        _progressController.add("Android Pipeline: Completed");
    }
  }

  Future<void> _spawnWorkers(int count, Future<void> Function() worker, String name) async {
    for (int i = 0; i < count; i++) {
      worker().ignore();
      await Future.delayed(const Duration(milliseconds: 50));
    }
    AdvancedLogger.info("FunnelService: Spawned $count $name workers.");
  }

  // --- WORKER LOOPS ---

  Future<void> _tcpWorker() async {
    while (_isRunning && !_cancelToken!.isCancelled) {
      VpnConfigWithMetrics? config;

      // Critical Section: Pop from Queue
      if (_tcpQueue.isNotEmpty) {
        config = _tcpQueue.removeAt(0);
        _activeTcpWorkers++;
      } else {
        // Queue empty? Wait a bit or exit if finished?
        // For decoupled pipeline, we just wait until everything is done or stopped.
        // We'll poll with delay.
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      try {
        _updateProgress();

        // STAGE 1: TCP Connect (Raw Dart Socket)
        final details = SingboxConfigGenerator.extractServerDetails(config.rawConfig);
        bool passed = false;

        if (details != null && details['host'] != null) {
           final host = details['host'] as String;
           final port = details['port'] as int? ?? 443;

           try {
             final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
             socket.destroy();
             passed = true;
           } catch (_) {
             // Failed
           }
        }

        if (passed) {
           // Push to HTTP Queue
           _tcpPassed++;
           _httpQueue.add(config);
        } else {
           await _configManager.markFailure(config!.id);
        }

      } catch (e) {
         AdvancedLogger.warn("TCP Worker Error: $e");
      } finally {
        _activeTcpWorkers--;
        _updateProgress();
      }
    }
  }

  Future<void> _httpWorker() async {
    while (_isRunning && !_cancelToken!.isCancelled) {
      VpnConfigWithMetrics? config;

      if (_httpQueue.isNotEmpty) {
        config = _httpQueue.removeAt(0);
        _activeHttpWorkers++;
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      try {
         _updateProgress();

         // STAGE 2: HTTP Connectivity (Strict 204)
         final result = await _tester.runTest(config!, mode: TestMode.connectivity);

         if (result.funnelStage == 2) { // Success
             _httpPassed++;
             await _configManager.updateConfigDirectly(result);
             _speedQueue.add(result);
         } else {
             await _configManager.markFailure(config.id);
         }

      } catch (e) {
         AdvancedLogger.warn("HTTP Worker Error: $e");
      } finally {
         _activeHttpWorkers--;
         _updateProgress();
      }
    }
  }

  Future<void> _speedWorker() async {
    while (_isRunning && !_cancelToken!.isCancelled) {
      VpnConfigWithMetrics? config;

      if (_speedQueue.isNotEmpty) {
         config = _speedQueue.removeAt(0);
         _activeSpeedWorkers++;
      } else {
         await Future.delayed(const Duration(milliseconds: 500));
         continue;
      }

      try {
         _updateProgress();

         // STAGE 3: Speed Test
         final result = await _tester.runTest(config!, mode: TestMode.speed);

         _speedFinished++;
         await _configManager.updateConfigDirectly(result);

      } catch (e) {
         AdvancedLogger.warn("Speed Worker Error: $e");
      } finally {
         _activeSpeedWorkers--;
         _updateProgress();
      }
    }
  }

  void _updateProgress() {
    if (!_isRunning) return;

    if (Platform.isAndroid) {
        final msg = "Testing: $_httpPassed/${_totalConfigs} | Active: $_activeHttpWorkers";
        _progressController.add(msg);
        return;
    }

    final msg = "TCP: $_tcpPassed | Valid: $_httpPassed | Speed: $_speedFinished | Queued: ${_tcpQueue.length + _httpQueue.length + _speedQueue.length}";
    _progressController.add(msg);

    // Check completion
    if (_tcpQueue.isEmpty && _httpQueue.isEmpty && _speedQueue.isEmpty &&
        _activeTcpWorkers == 0 && _activeHttpWorkers == 0 && _activeSpeedWorkers == 0) {
        // Debounce completion to ensure no race condition
        Future.delayed(const Duration(seconds: 2), () {
           if (_tcpQueue.isEmpty && _activeTcpWorkers == 0) {
              stop();
              _progressController.add("Completed");
           }
        });
    }
  }

  List<VpnConfigWithMetrics> _buildPriorityQueue(bool retestDead) {
    // Clone list to avoid concurrent modification issues
    final all = List<VpnConfigWithMetrics>.from(_configManager.allConfigs);

    // Categorize
    final tier1 = <VpnConfigWithMetrics>[]; // Retest (Known Good)
    final tier2 = <VpnConfigWithMetrics>[]; // Fresh
    final tier3 = <VpnConfigWithMetrics>[]; // Retry (Soft Fail)
    final dead = <VpnConfigWithMetrics>[];  // Dead (Hard Fail)

    final now = DateTime.now();

    for (final c in all) {
       if (c.funnelStage > 0) {
          if (c.lastTestedAt != null && now.difference(c.lastTestedAt!).inHours < 24) {
             tier1.add(c);
          } else {
             tier1.add(c);
          }
       } else if (c.funnelStage == 0 && c.failureCount == 0) {
          tier2.add(c); // Fresh
       } else if (c.failureCount < 3) {
          tier3.add(c); // Retry
       } else {
          dead.add(c);
       }
    }

    tier1.sort((a, b) => b.calculatedScore.compareTo(a.calculatedScore));

    final queue = [...tier1, ...tier2, ...tier3];
    if (retestDead) {
       queue.addAll(dead);
    }

    return queue;
  }
}

extension IgnoreFuture on Future {
  void ignore() {}
}
