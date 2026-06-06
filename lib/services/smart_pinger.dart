import 'dart:async';
import 'dart:io';
import '../utils/advanced_logger.dart';
import '../utils/test_constants.dart';
import '../utils/cancellable_operation.dart';

class PingResult {
  final String endpoint;
  final int latency; // milliseconds
  final bool isSuccess;
  final String? error;

  PingResult({
    required this.endpoint,
    required this.latency,
    required this.isSuccess,
    this.error,
  });
}

class SmartPingResult {
  final bool isOverallSuccess;
  final double averageLatency;
  final int successfulEndpoints;
  final int failedEndpoints;
  final List<PingResult> details;
  final String recommendation;

  SmartPingResult({
    required this.isOverallSuccess,
    required this.averageLatency,
    required this.successfulEndpoints,
    required this.failedEndpoints,
    required this.details,
    required this.recommendation,
  });
}

class SmartPinger {
  /// Smart ping with fault tolerance
  static Future<SmartPingResult> pingMultiple({
    required List<String> endpoints,
    CancelToken? cancelToken,
    int requiredSuccesses = 2,
    Duration? timeoutPerPing,
  }) async {
    final List<PingResult> allResults = [];
    final List<Future<PingResult>> futures = [];

    AdvancedLogger.info(
        '[SmartPing] Starting multi-endpoint ping test (Endpoints: ${endpoints.length})');

    final effectiveTimeout = timeoutPerPing ?? TestTimeouts.pingCheck;

    // Create independent futures for each endpoint
    for (final endpoint in endpoints) {
      futures.add(_pingWithRetry(
        endpoint,
        cancelToken,
        maxRetries: 2,
        timeout: effectiveTimeout,
      ));
    }

    // Run concurrently and collect results
    // We use Future.wait with eagerError: false to ensure we get all results even if some fail
    final results = await Future.wait(futures, eagerError: false);
    allResults.addAll(results);

    // Analyze results
    final successful = allResults.where((r) => r.isSuccess).toList();
    final failed = allResults.where((r) => !r.isSuccess).toList();

    // Generate recommendation
    String recommendation;
    bool overallSuccess;

    if (successful.length >= requiredSuccesses) {
      overallSuccess = true;
      recommendation =
          '✅ Network Healthy - ${successful.length}/${endpoints.length} endpoints responded';
    } else if (successful.isNotEmpty) {
      overallSuccess =
          true; // Still a success if at least one responded, though we might flag it
      recommendation =
          '⚠️ Weak Network - Only ${successful.length}/${endpoints.length} endpoints responded';
    } else {
      overallSuccess = false;
      recommendation = '❌ Network Failure - No endpoints responded';
    }

    final avg = successful.isNotEmpty
        ? successful.map((r) => r.latency).reduce((a, b) => a + b) /
            successful.length
        : -1.0;

    return SmartPingResult(
      isOverallSuccess: overallSuccess,
      averageLatency: avg,
      successfulEndpoints: successful.length,
      failedEndpoints: failed.length,
      details: allResults,
      recommendation: recommendation,
    );
  }

  /// Ping with retry capability
  static Future<PingResult> _pingWithRetry(
      String endpoint, CancelToken? cancelToken,
      {int maxRetries = 2, required Duration timeout}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final pingResult = await _pingSingle(
          endpoint,
          cancelToken,
          timeout: timeout,
        );

        if (pingResult.isSuccess) {
          return pingResult;
        }

        if (attempt < maxRetries) {
          AdvancedLogger.debug('[SmartPing] Retry $attempt for $endpoint');
          await Future.delayed(Duration(milliseconds: 200 * attempt));
        }
      } catch (e) {
        if (attempt == maxRetries) {
          return PingResult(
            endpoint: endpoint,
            latency: -1,
            isSuccess: false,
            error: 'All retries failed: $e',
          );
        }
      }
    }

    return PingResult(
      endpoint: endpoint,
      latency: -1,
      isSuccess: false,
      error: 'Max retries ($maxRetries) exceeded',
    );
  }

  /// Single endpoint ping using TCP connection
  static Future<PingResult> _pingSingle(
      String endpoint, CancelToken? cancelToken,
      {required Duration timeout}) async {
    final stopwatch = Stopwatch()..start();

    try {
      cancelToken?.throwIfCancelled();

      final uri = Uri.parse(endpoint);
      final host = uri.host;
      final port =
          uri.port == 0 ? (uri.scheme == 'https' ? 443 : 80) : uri.port;

      // TCP connection test
      final socket = await Socket.connect(
        host,
        port,
        timeout: timeout,
      );

      socket.destroy();
      stopwatch.stop();

      return PingResult(
        endpoint: endpoint,
        latency: stopwatch.elapsedMilliseconds,
        isSuccess: true,
        error: null,
      );
    } on SocketException catch (e) {
      stopwatch.stop();
      return PingResult(
        endpoint: endpoint,
        latency: -1,
        isSuccess: false,
        error: 'Socket error: ${e.message}',
      );
    } on TimeoutException {
      stopwatch.stop();
      return PingResult(
        endpoint: endpoint,
        latency: -1,
        isSuccess: false,
        error: 'Timeout after ${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      stopwatch.stop();
      return PingResult(
        endpoint: endpoint,
        latency: -1,
        isSuccess: false,
        error: 'Unexpected error: $e',
      );
    }
  }
}
