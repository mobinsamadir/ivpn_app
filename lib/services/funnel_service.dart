import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/vpn_config_with_metrics.dart';
import 'config_manager.dart';
import 'singbox_config_generator.dart';
import 'testers/ephemeral_tester.dart';
import '../utils/advanced_logger.dart';
import '../utils/cancellable_operation.dart';

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

  // Active Worker Counts (Windows)
  int _activeTcpWorkers = 0;
  int _activeHttpWorkers = 0;
  int _activeSpeedWorkers = 0;

  // Limits
  static const int _maxHttpWorkers = 5;
  static const int _maxSpeedWorkers = 2;

  // State
  bool _isRunning = false;
  CancelToken? _cancelToken;
  Timer? _uiThrottleTimer; // Throttled UI updater

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
    _uiThrottleTimer?.cancel();
    _tcpQueue.clear();
    _httpQueue.clear();
    _speedQueue.clear();

    // Kill any zombie processes (Windows)
    if (!Platform.isAndroid) {
       EphemeralTester.killAll();
    }

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

    // Start UI Throttle Timer (500ms)
    _startUiThrottle();

    // Android-specific parallel pipeline
    if (Platform.isAndroid) {
      // Don't await here so it runs in background
      _runAndroidFunnel(retestDead).ignore();
      return;
    }

    _progressController.add("Initializing Pipeline...");

    // 1. Populate TCP Queue (Initial Feed)
    final all = _buildPriorityQueue(retestDead);
    _totalConfigs = all.length;
    _tcpQueue.addAll(all);

    AdvancedLogger.info("FunnelService: Loaded ${_totalConfigs} configs into TCP Queue.");

    // 2. Start Worker Pools (Windows)
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

  void _startUiThrottle() {
    _uiThrottleTimer?.cancel();
    _uiThrottleTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (!_isRunning) {
           timer.cancel();
           return;
        }

        if (Platform.isAndroid) {
             final msg = "Testing: $_httpPassed/${_totalConfigs} (Active Futures: $_activeHttpWorkers)";
             _progressController.add(msg);

             // Check completion
             if (_tcpQueue.isEmpty && _activeHttpWorkers == 0 && _httpPassed > 0) { // Naive completion check
                 // The main loop handles completion message
             }
        } else {
             final msg = "TCP: $_tcpPassed | Valid: $_httpPassed | Speed: $_speedFinished | Queued: ${_tcpQueue.length + _httpQueue.length + _speedQueue.length}";
             _progressController.add(msg);

             // Check completion
             if (_tcpQueue.isEmpty && _httpQueue.isEmpty && _speedQueue.isEmpty &&
                 _activeTcpWorkers == 0 && _activeHttpWorkers == 0 && _activeSpeedWorkers == 0) {
                 // Debounce completion to ensure no race condition
                 Future.delayed(const Duration(seconds: 2), () {
                    if (_tcpQueue.isEmpty && _activeTcpWorkers == 0 && _isRunning) {
                       stop();
                       _progressController.add("Completed");
                    }
                 });
             }
        }
    });
  }

  // --- ANDROID PIPELINE (Refactored for Safety & Concurrency) ---
  Future<void> _runAndroidFunnel(bool retestDead) async {
    _progressController.add("Android Pipeline: Initializing...");

    final allConfigs = _buildPriorityQueue(retestDead);
    _totalConfigs = allConfigs.length;

    // Populate the queue first
    _tcpQueue.addAll(allConfigs); // Reuse TCP queue for source

    // Bounded Concurrency Pool
    const int maxConcurrent = 15;
    final List<Future<void>> activeFutures = [];

    AdvancedLogger.info("FunnelService (Android): Loaded $_totalConfigs configs. Starting pool...");

    while ((_tcpQueue.isNotEmpty || activeFutures.isNotEmpty) && _isRunning && !_cancelToken!.isCancelled) {
      // 1. Fill Pool
      while (activeFutures.length < maxConcurrent && _tcpQueue.isNotEmpty) {
         final config = _tcpQueue.removeAt(0);
         // Add worker to pool
         final future = _androidWorkerSafe(config);
         activeFutures.add(future);

         // Remove future from list when done
         future.then((_) => activeFutures.remove(future)).catchError((_) => activeFutures.remove(future));
      }

      // Update Active Counter for UI
      _activeHttpWorkers = activeFutures.length; // Reuse variable for stats

      // 2. Wait for at least one future to complete before looping?
      // Or just small delay to prevent tight loop if queue is empty but futures are running.
      // If we use Future.wait(activeFutures) it blocks.
      // Instead, we use `Future.any` or just a small delay loop which is safer/simpler.
      if (activeFutures.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 50));
      } else if (_tcpQueue.isEmpty) {
          break; // Done
      }
    }

    if (_isRunning) {
        stop();
        _progressController.add("Completed");
    }
  }

  Future<void> _androidWorkerSafe(VpnConfigWithMetrics config) async {
     try {
       // Delegate to EphemeralTester (Safe Mode)
       final result = await _tester.runTest(config, mode: TestMode.connectivity);

       if (result.funnelStage >= 2) {
          _httpPassed++;
          await _configManager.updateConfigDirectly(result);
       } else {
          // Silent failure
          // Optionally mark as failed in manager?
          // await _configManager.markFailure(config.id); // Maybe too much IO?
       }
     } catch (e) {
       AdvancedLogger.warn("Android Worker Exception (Safe Catch): $e");
     }
  }

  // --- WINDOWS WORKERS ---

  Future<void> _spawnWorkers(int count, Future<void> Function() worker, String name) async {
    for (int i = 0; i < count; i++) {
      worker().ignore();
      await Future.delayed(const Duration(milliseconds: 50));
    }
    AdvancedLogger.info("FunnelService: Spawned $count $name workers.");
  }

  Future<void> _tcpWorker() async {
    while (_isRunning && !_cancelToken!.isCancelled) {
      VpnConfigWithMetrics? config;

      // Critical Section: Pop from Queue
      if (_tcpQueue.isNotEmpty) {
        // RESERVATION LOGIC:
        // Even if semaphore is "full" (all 5 used), TCP should ideally run fast.
        // But EphemeralTester uses a global semaphore. We rely on its fairness.
        // The bottleneck is EphemeralTester ONLY for Stage 2/3 (Process spawn).
        // Stage 1 (TCP) here is pure Dart socket and does NOT use EphemeralTester's semaphore!
        // So TCP workers are only limited by _maxTcpWorkers (5) and OS ports.
        config = _tcpQueue.removeAt(0);
        _activeTcpWorkers++;
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      try {
        // STAGE 1: TCP Connect (Raw Dart Socket)
        // This is FAST and does NOT use the global Semaphore(5) in EphemeralTester.
        // It runs in parallel with heavy tests.
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
           _tcpPassed++;
           _httpQueue.add(config);
        } else {
           await _configManager.markFailure(config!.id);
        }

      } catch (e) {
         AdvancedLogger.warn("TCP Worker Error: $e");
      } finally {
        _activeTcpWorkers--;
      }
    }
  }

  Future<void> _httpWorker() async {
    while (_isRunning && !_cancelToken!.isCancelled) {
      VpnConfigWithMetrics? config;

      // QUOTA LOGIC:
      // Limit concurrent heavy tests (HTTP/Speed) to avoid starving the Semaphore completely.
      // If we have 5 max slots, let's limit HTTP+Speed to 3, leaving 2 free for other things?
      // Actually, EphemeralTester semaphore controls *execution*.
      // We should just check queue.
      if (_httpQueue.isNotEmpty) {
        // Simple Quota: Don't take job if too many active heavy workers?
        // Let's rely on the worker count passed to spawnWorkers (5).
        // But wait, spawnWorkers spawns 'n' loops.
        // If we spawn 5 HTTP workers and 2 Speed workers, that's 7 concurrent loops trying to get the 5 Semaphore slots.
        // This is fine, they will just queue up at the semaphore.
        config = _httpQueue.removeAt(0);
        _activeHttpWorkers++;
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      try {
         // STAGE 2: HTTP Connectivity (Strict 204)
         // This USES the Semaphore(5) inside EphemeralTester
         final result = await _tester.runTest(config, mode: TestMode.connectivity);

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
         // STAGE 3: Speed Test
         // This USES the Semaphore(5) inside EphemeralTester
         final result = await _tester.runTest(config, mode: TestMode.speed);

         _speedFinished++;
         await _configManager.updateConfigDirectly(result);

      } catch (e) {
         AdvancedLogger.warn("Speed Worker Error: $e");
      } finally {
         _activeSpeedWorkers--;
      }
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
