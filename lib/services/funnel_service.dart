import 'dart:async';
import 'dart:collection';
import '../models/vpn_config_with_metrics.dart';
import 'config_manager.dart';
import 'testers/ephemeral_tester.dart';
import '../utils/advanced_logger.dart';
import '../utils/cancellable_operation.dart';

class FunnelService {
  static final FunnelService _instance = FunnelService._internal();
  factory FunnelService() => _instance;
  FunnelService._internal();

  final ConfigManager _configManager = ConfigManager();
  final EphemeralTester _tester = EphemeralTester();

  // Concurrency Control
  static const int _maxConcurrentTests = 5;
  int _activeTests = 0;
  final List<Completer<void>> _waitingQueue = [];

  // State
  bool _isRunning = false;
  CancelToken? _cancelToken;

  // Progress Stream
  final _progressController = StreamController<String>.broadcast();
  Stream<String> get progressStream => _progressController.stream;

  // Stats
  int _totalToTest = 0;
  int _testedCount = 0;

  Future<void> stop() async {
    _isRunning = false;
    _cancelToken?.cancel();
    _activeTests = 0;
    _waitingQueue.clear();
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
    _testedCount = 0;

    AdvancedLogger.info("FunnelService: Starting Funnel (RetestDead: $retestDead)");
    _progressController.add("Initializing...");

    // 1. Build & Sort Queue
    List<VpnConfigWithMetrics> queue = _buildPriorityQueue(retestDead);
    _totalToTest = queue.length;

    AdvancedLogger.info("FunnelService: Queue built with ${_totalToTest} configs.");
    _progressController.add("Queue: $_totalToTest configs");

    // 2. Process Queue with Concurrency Limit
    final List<Future<void>> futures = [];

    for (final config in queue) {
      if (!_isRunning || _cancelToken!.isCancelled) break;

      // Wait for slot
      await _acquireSlot();

      if (!_isRunning || _cancelToken!.isCancelled) {
         _releaseSlot();
         break;
      }

      final f = _runTestSafe(config).then((_) {
         _releaseSlot();
      });
      futures.add(f);
    }

    // Wait for remaining tests
    await Future.wait(futures);

    _isRunning = false;
    _progressController.add("Completed");
    AdvancedLogger.info("FunnelService: Funnel Complete.");
  }

  Future<void> _acquireSlot() {
    if (_activeTests < _maxConcurrentTests) {
      _activeTests++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waitingQueue.add(completer);
    return completer.future;
  }

  void _releaseSlot() {
    _activeTests--;
    if (_waitingQueue.isNotEmpty) {
      _activeTests++; // Re-occupy immediately for the waiting task
      _waitingQueue.removeAt(0).complete();
    }
  }

  Future<void> _runTestSafe(VpnConfigWithMetrics config) async {
    try {
       // Update UI (Testing...)
       _progressController.add("Testing (${_testedCount + 1}/$_totalToTest): ${config.name}");

       final result = await _tester.runTest(config);

       // Update ConfigManager
       // We use updateConfigDirectly to persist the result (metrics, stages, etc.)
       await _configManager.updateConfigDirectly(result);

       _testedCount++;

    } catch (e) {
       AdvancedLogger.error("FunnelService: Error testing ${config.name}: $e");
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
       // Logic for Tiers
       if (c.funnelStage > 0) {
          // If tested successfully recently (e.g. < 24h), it's Tier 1
          if (c.lastTestedAt != null && now.difference(c.lastTestedAt!).inHours < 24) {
             tier1.add(c);
          } else {
             // Old success, treat as Tier 1 but lower priority? No, Tier 1 is "Retest".
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

    // Sort Tier 1 by Speed/Score to re-verify best ones first
    tier1.sort((a, b) => b.calculatedScore.compareTo(a.calculatedScore));

    // Combine
    final queue = [...tier1, ...tier2, ...tier3];
    if (retestDead) {
       queue.addAll(dead);
    }

    return queue;
  }
}
