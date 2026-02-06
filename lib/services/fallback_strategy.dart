import '../services/test_job.dart';
import '../utils/advanced_logger.dart';
import '../utils/cancellable_operation.dart';

class TestFallbackStrategy {
  /// Defines how a timed-out test should recover
  static void triggerFallback(TestType type, String jobId, CancelToken token) {
    AdvancedLogger.info('[Fallback] Triggering fallback for $type (Job: $jobId)');
    
    switch (type) {
      case TestType.speed:
        _handleSpeedFallback(jobId, token);
        break;
      case TestType.health:
        _handleHealthFallback(jobId, token);
        break;
      default:
        AdvancedLogger.info('[Fallback] No specific fallback for $type');
    }
  }

  static void _handleSpeedFallback(String jobId, CancelToken token) {
    AdvancedLogger.warn('[Fallback] Speed Test Timeout: Recommending fallback to Medium/Small payload.');
    // In a real implementation, this would re-enqueue a lighter job 
    // or notify the UI to adjust expectations.
  }

  static void _handleHealthFallback(String jobId, CancelToken token) {
    AdvancedLogger.warn('[Fallback] Health Check Timeout: Reducing endpoint count for next attempt.');
  }
}
