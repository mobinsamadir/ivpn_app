import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/vpn_config_with_metrics.dart';
import 'config_manager.dart'; // Correct relative import (same folder)
import 'singbox_config_generator.dart';
import 'testers/ephemeral_tester.dart';
import '../utils/advanced_logger.dart';

// Top-level function for priority queue building in isolate
List<VpnConfigWithMetrics> _buildQueueInIsolate(Map<String, dynamic> args) {
  final List<VpnConfigWithMetrics> allConfigs = args['configs'] as List<VpnConfigWithMetrics>;
  final bool retestDead = args['retestDead'] as bool;

  // Categorize
  final tier1 = <VpnConfigWithMetrics>[]; // Retest (Known Good < 24h)
  final tier2 = <VpnConfigWithMetrics>[]; // Fresh / Untested
  final tier3 = <VpnConfigWithMetrics>[]; // Retry (Soft Fail)
  final dead = <VpnConfigWithMetrics>[];  // Dead (Hard Fail)

  final now = DateTime.now();

  for (final c in allConfigs) {
     if (c.funnelStage > 0) {
        if (c.lastTestedAt != null && now.difference(c.lastTestedAt!).inHours < 24) {
           tier1.add(c);
        } else {
           tier1.add(c); // Old good configs
        }
     } else if (c.funnelStage == 0 && c.failureCount == 0) {
        tier2.add(c); // Fresh
     } else if (c.failureCount < 3) {
        tier3.add(c); // Retry
     } else {
        dead.add(c);
     }
  }

  // Sort Tier 1 by score (Best first)
  tier1.sort((a, b) => b.calculatedScore.compareTo(a.calculatedScore));

  final queue = [...tier1, ...tier2, ...tier3];
  if (retestDead) {
     queue.addAll(dead);
  }

  return queue;
}

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
  static const int _maxTcpWorkers = 10;
  static const int _maxHttpWorkers = 5;
  static const int _maxSpeedWorkers = 2;

  // State
  bool _isRunning = false;
  bool _stopRequested = false;
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
    _stopRequested = true;
    _isRunning = false;
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
    _stopRequested = false;
    _tcpPassed = 0;
    _httpPassed = 0;
    _speedFinished = 0;

    AdvancedLogger.info("FunnelService: Starting Pipeline (RetestDead: $retestDead)");

    // Start UI Throttle Timer (500ms)
    _startUiThrottle();

    _progressController.add("Initializing Pipeline...");

    // 1. Populate TCP Queue (Initial Feed)
    // Offload to isolate
    final all = await compute(_buildQueueInIsolate, {
       'configs': _configManager.allConfigs,
       'retestDead': retestDead,
    });

    _totalConfigs = all.length;
    _tcpQueue.addAll(all);

    AdvancedLogger.info("FunnelService: Loaded $_totalConfigs configs into TCP Queue.");

    // 2. Start Worker Pools
    // We spawn fixed number of loops that pull from queues
    _spawnWorkers(_maxTcpWorkers, _tcpWorker, "TCP");
    _spawnWorkers(_maxHttpWorkers, _httpWorker, "HTTP");
    _spawnWorkers(_maxSpeedWorkers, _speedWorker, "Speed");
  }

  void _startUiThrottle() {
    _uiThrottleTimer?.cancel();
    _uiThrottleTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (!_isRunning) {
           timer.cancel();
           return;
        }

        final msg = "TCP: $_tcpPassed | HTTP: $_httpPassed | Speed: $_speedFinished | Queued: ${_tcpQueue.length + _httpQueue.length + _speedQueue.length}";
        _progressController.add(msg);

        // Check completion
        if (_tcpQueue.isEmpty && _httpQueue.isEmpty && _speedQueue.isEmpty &&
            _activeTcpWorkers == 0 && _activeHttpWorkers == 0 && _activeSpeedWorkers == 0) {

            // Debounce completion
            Future.delayed(const Duration(seconds: 2), () {
               if (_tcpQueue.isEmpty && _activeTcpWorkers == 0 && _isRunning) {
                  stop();
                  _progressController.add("Completed");
               }
            });
        }
    });
  }

  // --- WORKER SPAWNER ---
  void _spawnWorkers(int count, Future<void> Function() worker, String name) {
    for (int i = 0; i < count; i++) {
      worker(); // Fire and forget
    }
    AdvancedLogger.info("FunnelService: Spawned $count $name workers.");
  }

  // --- WORKERS ---

  Future<void> _tcpWorker() async {
    while (_isRunning && !_stopRequested) {
      VpnConfigWithMetrics? config;

      // Critical Section: Pop
      if (_tcpQueue.isNotEmpty) {
        config = _tcpQueue.removeAt(0);
        _activeTcpWorkers++;
      } else {
        // If queue empty, wait a bit then check again
        await Future.delayed(const Duration(milliseconds: 200));
        // If still empty and no new tasks likely, just loop
        continue;
      }

      try {
        // STAGE 1: TCP Connect (Raw Dart Socket)
        bool passed = false;

        // Extract host/port
        final details = SingboxConfigGenerator.extractServerDetails(config.rawConfig);

        if (details != null && details['host'] != null) {
           final host = details['host'] as String;
           final port = details['port'] as int? ?? 443;

           try {
             // 2-second timeout for fast fail
             final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
             socket.destroy();
             passed = true;
           } catch (_) {
             // Failed
           }
        }

        if (passed) {
           _tcpPassed++;
           // Promote to HTTP Queue
           _httpQueue.add(config);

           // Optimistic Update: Mark TCP passed in UI (optional, but good for feedback)
           // We don't save to disk yet to avoid IO thrashing
        } else {
           // Failed TCP - Mark Dead
           await _configManager.markFailure(config.id);
        }

      } catch (e) {
         AdvancedLogger.warn("TCP Worker Error: $e");
      } finally {
        _activeTcpWorkers--;
      }
    }
  }

  Future<void> _httpWorker() async {
    while (_isRunning && !_stopRequested) {
      VpnConfigWithMetrics? config;

      if (_httpQueue.isNotEmpty) {
        config = _httpQueue.removeAt(0);
        _activeHttpWorkers++;
      } else {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      try {
         // STAGE 2: HTTP Connectivity (Strict 204)
         // This uses EphemeralTester which handles the Semaphore/Locking
         final result = await _tester.runTest(config, mode: TestMode.connectivity);

         if (result.funnelStage >= 2) { // Success (2 or 3)
             _httpPassed++;

             // Update Manager (triggers Sort & UI update)
             await _configManager.updateConfigDirectly(result);

             // Promote to Speed Queue
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
    while (_isRunning && !_stopRequested) {
      VpnConfigWithMetrics? config;

      if (_speedQueue.isNotEmpty) {
         config = _speedQueue.removeAt(0);
         _activeSpeedWorkers++;
      } else {
         await Future.delayed(const Duration(milliseconds: 200));
         continue;
      }

      try {
         // STAGE 3: Speed Test
         final result = await _tester.runTest(config, mode: TestMode.speed);

         if (result.funnelStage == 3) {
            _speedFinished++;
            await _configManager.updateConfigDirectly(result);
         }
         // If speed test fails (but HTTP passed), we still keep it as Stage 2 valid
         // EphemeralTester handles this (returns Stage 2 result if Stage 3 fails)

      } catch (e) {
         AdvancedLogger.warn("Speed Worker Error: $e");
      } finally {
         _activeSpeedWorkers--;
      }
    }
  }

}
