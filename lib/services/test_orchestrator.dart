import 'dart:async';
import 'test_queue.dart';
import 'test_job.dart';
import '../utils/test_constants.dart';
import '../utils/advanced_logger.dart';
import '../utils/cancellable_operation.dart';

class TestOrchestrator {
  static final TestQueue speedQueue = TestQueue(category: 'speed');
  static final TestQueue stabilityQueue = TestQueue(category: 'stability');
  static final TestQueue healthQueue = TestQueue(category: 'health');
  static final TestQueue pingQueue = TestQueue(category: 'ping');
  
  // Health check with timeout
  static Future<void> enqueueHealthCheck(
    Future<void> Function(CancelToken, String) task, {
    String? name,
    bool quick = true,
  }) async {
    final timeout = quick 
        ? TestTimeouts.quickHealthCheck
        : TestTimeouts.fullHealthCheck;
    
    return healthQueue.enqueue(
      task,
      name: name ?? (quick ? 'Quick Health Check' : 'Full Health Check'),
      timeout: timeout,
      type: TestType.health,
    );
  }
  
  // Speed test with timeout and optional fallback
  static Future<void> enqueueSpeedTest(
    Future<void> Function(CancelToken, String) task, {
    String? name,
    Duration? customTimeout,
    bool enableFallback = true,
  }) async {
    final timeout = customTimeout ?? TestTimeouts.speedTestSingle;
    
    return speedQueue.enqueue(
      task,
      name: name ?? 'Speed Test',
      timeout: timeout,
      type: enableFallback ? TestType.speed : null,
    );
  }
  
  // Stability test with timeout
  static Future<void> enqueueStabilityTest(
    Future<void> Function(CancelToken, String) task, {
    String? name,
  }) async {
    return stabilityQueue.enqueue(
      task,
      name: name ?? 'Stability Test',
      timeout: TestTimeouts.stabilityTest,
      type: TestType.stability,
    );
  }
  
  // Ping test with timeout
  static Future<void> enqueuePingTest(
    Future<void> Function(CancelToken, String) task, {
    String? name,
  }) async {
    return pingQueue.enqueue(
      task,
      name: name ?? 'Ping Test',
      timeout: TestTimeouts.pingCheck,
      type: TestType.ping,
    );
  }
  
  // Adaptive speed test with timeout
  static Future<void> enqueueAdaptiveTest(
    Future<void> Function(CancelToken, String) task, {
    String? name,
  }) async {
    return speedQueue.enqueue(
      task,
      name: name ?? 'Adaptive Speed Test',
      timeout: TestTimeouts.adaptiveSpeedTest,
      type: TestType.speed,
    );
  }
  
  // Cancellation methods
  static void cancelSpeedTests() => speedQueue.cancelAll();
  static void cancelStabilityTests() => stabilityQueue.cancelAll();
  
  static void cancelAll() {
    AdvancedLogger.info('[Orchestrator] Cancelling ALL tests');
    speedQueue.cancelAll();
    stabilityQueue.cancelAll();
    healthQueue.cancelAll();
    pingQueue.cancelAll();
  }
  
  // Status reporting
  static Map<String, dynamic> getStatus() {
    return {
      'speedQueue': speedQueue.queueLength,
      'stabilityQueue': stabilityQueue.queueLength,
      'healthQueue': healthQueue.queueLength,
      'pingQueue': pingQueue.queueLength,
      'isAnyBusy': speedQueue.isBusy || 
                   stabilityQueue.isBusy || 
                   healthQueue.isBusy || 
                   pingQueue.isBusy,
    };
  }
  
  static String getStatusString() {
    final status = getStatus();
    return 'Queued: S:${status['speedQueue']} B:${status['stabilityQueue']} H:${status['healthQueue']} P:${status['pingQueue']}';
  }
}
