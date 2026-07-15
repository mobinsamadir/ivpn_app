import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/vpn_config_with_metrics.dart';
import 'config_manager.dart'; // Correct relative import (same folder)
import 'singbox_config_generator.dart';
import 'testers/ephemeral_tester.dart';
import '../utils/advanced_logger.dart';

// Top-level function for batch processing in Isolate
Map<String, Map<String, dynamic>> batchProcessConfigsInIsolate(
  List<Map<String, String>> configs,
) {
  final Map<String, Map<String, dynamic>> results = {};
  for (final config in configs) {
    try {
      final details = SingboxConfigGenerator.extractServerDetails(
        config['rawConfig']!,
      );
      if (details != null && details['host'] != null) {
        results[config['id']!] = details;
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

  static int _getDynamicWorkerCount(int maxAllowed) {
    try {
      final cores = Platform.numberOfProcessors;
      // Use at least 2 workers, but don't exceed maxAllowed or cores
      return min(max(cores, 2), maxAllowed);
    } catch (e) {
      return 2; // Safe fallback
    }
  }

  // Limits

  static int get _maxTcpWorkers =>
      Platform.isWindows ? 2 : _getDynamicWorkerCount(6);
  static int get _maxHttpWorkers =>
      Platform.isWindows ? 2 : _getDynamicWorkerCount(3);
  static int get _maxSpeedWorkers => 1;

  // State
  bool _isRunning = false;
  bool _stopRequested = false;
  Timer? _uiThrottleTimer; // Throttled UI updater

  // Stats
  int _totalConfigs = 0;
  int _tcpPassed = 0;
  int _httpPassed = 0;
  int _speedFinished = 0;
  int _totalFailed = 0;

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
    _printTelemetrySummary();
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
    _totalFailed = 0;

    AdvancedLogger.info(
      "FunnelService: Starting Pipeline (RetestDead: $retestDead)",
    );

    // Start UI Throttle Timer (500ms)
    _startUiThrottle();

    _progressController.add("Initializing Pipeline...");

    // 1. Populate TCP Queue (Initial Feed) - Run locally to avoid isolate serialization overhead
    final allConfigs = _configManager.allConfigs;
    final favorites = <VpnConfigWithMetrics>[];
    final validated = <VpnConfigWithMetrics>[];
    final fresh = <VpnConfigWithMetrics>[];
    final softFail = <VpnConfigWithMetrics>[];
    final dead = <VpnConfigWithMetrics>[];
    final now = DateTime.now();

    for (final c in allConfigs) {
      if (!retestDead && c.lastTestedAt != null) {
        final hoursSinceTested = now.difference(c.lastTestedAt!).inHours;
        if (hoursSinceTested < 2) continue;
      }
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

    int compareScore(VpnConfigWithMetrics a, VpnConfigWithMetrics b) {
      return b.calculatedScore.compareTo(a.calculatedScore);
    }

    favorites.sort(compareScore);
    validated.sort(compareScore);

    final all = [...favorites, ...validated, ...fresh, ...softFail];
    if (retestDead) {
      all.addAll(dead);
    }

    _totalConfigs = all.length;
    _tcpQueue.addAll(all);

    // 1.5 Batch Pre-process Configs (Extract Host/Port in Isolate)
    try {
      AdvancedLogger.info(
        "FunnelService: Pre-processing $_totalConfigs configs in Isolate...",
      );

      // Map to lightweight representation to avoid Isolate serialization overload
      final lightweightConfigs =
          all.map((c) => {'id': c.id, 'rawConfig': c.rawConfig}).toList();

      // Batch the processing to avoid huge object transfers
      _cachedServerDetails = {};
      final int batchSize = 200;
      for (int i = 0; i < lightweightConfigs.length; i += batchSize) {
        final chunk = lightweightConfigs.sublist(i, (i + batchSize > lightweightConfigs.length) ? lightweightConfigs.length : i + batchSize);
        final chunkResults = await compute(batchProcessConfigsInIsolate, chunk);
        _cachedServerDetails.addAll(chunkResults);
      }

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

  void _printTelemetrySummary() {
    debugPrint("--- [TELEMETRY] FUNNEL RUN SUMMARY ---");
    debugPrint("Total Tested: $_totalConfigs");
    debugPrint("Total Passed TCP: $_tcpPassed");
    debugPrint("Total Passed HTTP: $_httpPassed");
    debugPrint("Total Passed Speed: $_speedFinished");
    debugPrint("Total Failed: $_totalFailed");
    debugPrint("--------------------------------------");
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
            _printTelemetrySummary();
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
      // Yield to event loop to prevent ANR/OOM on Android
      await Future.delayed(const Duration(milliseconds: 50));
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
          _totalFailed++;
          debugPrint(
            "[TELEMETRY] ${config.name} | LastPassedStage: 0 | PingDuration: N/A | ExactException: TCP Connect Timeout",
          );
          await _configManager.markFailure(config.id);
        }
      } catch (e) {
        _totalFailed++;
        debugPrint(
          "[TELEMETRY] ${config.name} | LastPassedStage: 0 | PingDuration: N/A | ExactException: $e",
        );
        AdvancedLogger.warn("TCP Worker Error: $e");
      } finally {
        _activeTcpWorkers--;
      }
    }
  }

  Future<void> _httpWorker() async {
    while (_isRunning && !_stopRequested) {
      // Yield to event loop to prevent ANR/OOM on Android
      await Future.delayed(const Duration(milliseconds: 50));
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
          debugPrint(
            "[TELEMETRY] ${config.name} | LastPassedStage: 2 | PingDuration: ${result.currentPing} | ExactException: None",
          );

          // Update Manager (triggers Sort & UI update)
          await _configManager.updateConfigDirectly(result);

          // Promote to Speed Queue
          _speedQueue.add(result);
        } else {
          _totalFailed++;
          debugPrint(
            "[TELEMETRY] ${config.name} | LastPassedStage: 1 | PingDuration: ${result.currentPing} | ExactException: HTTP Failed (No 204)",
          );
          await _configManager.markFailure(config.id);
        }
      } catch (e) {
        _totalFailed++;
        debugPrint(
          "[TELEMETRY] ${config.name} | LastPassedStage: 1 | PingDuration: N/A | ExactException: $e",
        );
        AdvancedLogger.warn("HTTP Worker Error: $e");
      } finally {
        _activeHttpWorkers--;
      }
    }
  }

  Future<void> _speedWorker() async {
    while (_isRunning && !_stopRequested) {
      // Yield to event loop to prevent ANR/OOM on Android
      await Future.delayed(const Duration(milliseconds: 50));
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
