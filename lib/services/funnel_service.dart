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
  final List<VpnConfigWithMetrics> allConfigs =
      args['configs'] as List<VpnConfigWithMetrics>;
  final bool retestDead = args['retestDead'] as bool;

  // Priority order: Favorites > Validated (funnelStage > 0) > Fresh/Untested > Soft Fail > Dead
  final favorites = <VpnConfigWithMetrics>[];
  final validated = <VpnConfigWithMetrics>[];
  final fresh = <VpnConfigWithMetrics>[];
  final softFail = <VpnConfigWithMetrics>[];
  final dead = <VpnConfigWithMetrics>[];

  for (final c in allConfigs) {
    if (c.isFavorite) {
      favorites.add(c);
    } else if (c.isValidated || c.funnelStage > 0) {
      validated.add(c);
    } else if (c.funnelStage == 0 && c.failureCount == 0) {
      fresh.add(c);
    } else if (c.failureCount < 3) {
      softFail.add(c);
    } else {
      dead.add(c);
    }
  }

  // Sort groups internally by score (best first)
  int compareScore(VpnConfigWithMetrics a, VpnConfigWithMetrics b) {
    return b.calculatedScore.compareTo(a.calculatedScore);
  }

  favorites.sort(compareScore);
  validated.sort(compareScore);

  final queue = [...favorites, ...validated, ...fresh, ...softFail];
  if (retestDead) {
    queue.addAll(dead);
  }

  return queue;
}

// Top-level function for batch processing in Isolate
Map<String, Map<String, dynamic>> batchProcessConfigsInIsolate(
  List<VpnConfigWithMetrics> configs,
) {
  final Map<String, Map<String, dynamic>> results = {};
  for (final config in configs) {
    try {
      final details = SingboxConfigGenerator.extractServerDetails(
        config.rawConfig,
      );
      if (details != null && details['host'] != null) {
        results[config.id] = details;
      }
    } catch (e) {
      // Silently ignore malformed configs to prevent batch crash
    }
  }
  return results;
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

  // Cache for pre-processed details
  Map<String, Map<String, dynamic>> _cachedServerDetails = {};

  // Active Worker Counts
  int _activeTcpWorkers = 0;
  int _activeHttpWorkers = 0;
  int _activeSpeedWorkers = 0;

  // Limits
  // Limits
  static final int _maxTcpWorkers = Platform.isWindows ? 2 : 10;
  static final int _maxHttpWorkers = Platform.isWindows ? 2 : 5;
  static final int _maxSpeedWorkers = Platform.isWindows ? 1 : 2;

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

    AdvancedLogger.info(
      "FunnelService: Starting Pipeline (RetestDead: $retestDead)",
    );

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

    // 1.5 Batch Pre-process Configs (Extract Host/Port in Isolate)
    try {
      AdvancedLogger.info(
        "FunnelService: Pre-processing $_totalConfigs configs in Isolate...",
      );
      _cachedServerDetails = await compute(batchProcessConfigsInIsolate, all);
      AdvancedLogger.info(
        "FunnelService: Pre-processing complete. Cached ${_cachedServerDetails.length} valid details.",
      );
    } catch (e) {
      AdvancedLogger.error("FunnelService: Batch processing failed: $e");
      _cachedServerDetails = {};
    }

    AdvancedLogger.info(
      "FunnelService: Loaded $_totalConfigs configs into TCP Queue.",
    );

    // 2. Start Worker Pools
    // We spawn fixed number of loops that pull from queues
    _spawnWorkers(_maxTcpWorkers, _tcpWorker, "TCP");
    _spawnWorkers(_maxHttpWorkers, _httpWorker, "HTTP");
    _spawnWorkers(_maxSpeedWorkers, _speedWorker, "Speed");
  }

  void _startUiThrottle() {
    _uiThrottleTimer?.cancel();
    _uiThrottleTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (!_isRunning) {
        timer.cancel();
        return;
      }

      final msg =
          "TCP: $_tcpPassed | HTTP: $_httpPassed | Speed: $_speedFinished | Queued: ${_tcpQueue.length + _httpQueue.length + _speedQueue.length}";
      _progressController.add(msg);

      // Check completion
      if (_tcpQueue.isEmpty &&
          _httpQueue.isEmpty &&
          _speedQueue.isEmpty &&
          _activeTcpWorkers == 0 &&
          _activeHttpWorkers == 0 &&
          _activeSpeedWorkers == 0) {
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

        // Use Cached Details to avoid Main Thread Parsing
        final details = _cachedServerDetails[config.id];

        if (details != null && details['host'] != null) {
          final host = details['host'] as String;
          final port = details['port'] as int? ?? 443;

          try {
            // 2-second timeout for fast fail
            final socket = await Socket.connect(
              host,
              port,
              timeout: const Duration(seconds: 2),
            );
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
        final result = await _tester.runTest(
          config,
          mode: TestMode.connectivity,
        );

        if (result.funnelStage >= 2) {
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
