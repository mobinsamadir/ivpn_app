import 'dart:async';
import 'dart:io';
import '../utils/advanced_logger.dart';
import 'package:flutter/foundation.dart';
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
      '[SmartPing] Starting multi-endpoint ping test (Endpoints: ${endpoints.length})',
    );

    final effectiveTimeout = timeoutPerPing ?? TestTimeouts.pingCheck;

    // Create independent futures for each endpoint
    for (final endpoint in endpoints) {
      futures.add(
        pingWithRetry(
          endpoint,
          cancelToken,
          maxRetries: 2,
          timeout: effectiveTimeout,
        ),
      );
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
  @visibleForTesting
  static Future<PingResult> pingWithRetry(
    String endpoint,
    CancelToken? cancelToken, {
    int maxRetries = 2,
    required Duration timeout,
    Future<PingResult> Function(String, CancelToken?,
            {required Duration timeout})?
        pingSingleInjector,
  }) async {
    final pingFunc = pingSingleInjector ?? _pingSingle;
    final completer = Completer<PingResult>();
    int failedAttempts = 0;
    String? lastError;

    void handleResult(PingResult result) {
      if (completer.isCompleted) return;
      if (result.isSuccess) {
        completer.complete(result);
      } else {
        failedAttempts++;
        lastError = result.error;
        if (failedAttempts == maxRetries) {
          completer.complete(PingResult(
            endpoint: endpoint,
            latency: -1,
            isSuccess: false,
            error: 'All retries failed: $lastError',
          ));
        }
      }
    }

    void handleError(Object e, StackTrace st) {
      if (completer.isCompleted) return;
      if (e is OperationCancelledException) {
        completer.completeError(e, st);
      } else {
        failedAttempts++;
        lastError = e.toString();
        if (failedAttempts == maxRetries) {
          completer.complete(PingResult(
            endpoint: endpoint,
            latency: -1,
            isSuccess: false,
            error: 'All retries failed: $lastError',
          ));
        }
      }
    }

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        if (!completer.isCompleted) {
          completer.completeError(OperationCancelledException(
              cancelToken?.reason?.toString() ?? 'Cancelled'));
        }
        break;
      }

      if (completer.isCompleted) break;

      pingFunc(endpoint, cancelToken, timeout: timeout)
          .then(handleResult)
          .catchError(handleError);

      if (attempt < maxRetries && !completer.isCompleted) {
        try {
          await Future.any([
            Future.delayed(const Duration(milliseconds: 500)),
            completer.future,
          ]);
        } catch (_) {
          // Exception from completer.future will be handled by the caller awaiting it
        }
      }
    }

    return completer.future;
  }

  /// Single endpoint ping using TCP connection
  static Future<PingResult> _pingSingle(
    String endpoint,
    CancelToken? cancelToken, {
    required Duration timeout,
  }) async {
    cancelToken?.throwIfCancelled();

    final args = {
      'endpoint': endpoint,
      'timeoutInMilliseconds': timeout.inMilliseconds,
    };

    final resultData = await compute(_isolatePingSingle, args);

    cancelToken?.throwIfCancelled();

    return PingResult(
      endpoint: resultData['endpoint'] as String,
      latency: resultData['latency'] as int,
      isSuccess: resultData['isSuccess'] as bool,
      error: resultData['error'] as String?,
    );
  }
}

/// Top-level Isolate entry point for ping testing
Future<Map<String, dynamic>> _isolatePingSingle(
    Map<String, dynamic> args) async {
  final endpoint = args['endpoint'] as String;
  final timeoutInMilliseconds = args['timeoutInMilliseconds'] as int;
  final timeout = Duration(milliseconds: timeoutInMilliseconds);

  final stopwatch = Stopwatch()..start();

  try {
    final uri = Uri.parse(endpoint);
    final host = uri.host;
    final port = uri.port == 0 ? (uri.scheme == 'https' ? 443 : 80) : uri.port;

    // TCP connection test inside isolate
    final socket = await Socket.connect(host, port, timeout: timeout);

    socket.destroy();
    stopwatch.stop();

    return {
      'endpoint': endpoint,
      'latency': stopwatch.elapsedMilliseconds,
      'isSuccess': true,
      'error': null,
    };
  } on SocketException catch (e) {
    stopwatch.stop();
    return {
      'endpoint': endpoint,
      'latency': -1,
      'isSuccess': false,
      'error': 'Socket error: ${e.message}',
    };
  } on TimeoutException {
    stopwatch.stop();
    return {
      'endpoint': endpoint,
      'latency': -1,
      'isSuccess': false,
      'error': 'Timeout after ${stopwatch.elapsedMilliseconds}ms',
    };
  } catch (e) {
    stopwatch.stop();
    return {
      'endpoint': endpoint,
      'latency': -1,
      'isSuccess': false,
      'error': 'Unexpected error: $e',
    };
  }
}
