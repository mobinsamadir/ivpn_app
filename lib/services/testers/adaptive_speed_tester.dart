import 'dart:async';
import 'dart:io';
import '../../utils/cancellable_operation.dart';
import '../../models/testing/test_results.dart';
import '../../utils/endpoints.dart';
import '../../utils/advanced_logger.dart';
import '../../utils/test_constants.dart';
import '../../utils/cleanup_utils.dart';

class SpeedTestResult {
  final double mbps;
  final String status;
  final Duration duration;

  SpeedTestResult(this.mbps, this.status, this.duration);
}

class AdaptiveSpeedTester {
  final int httpPort;
  final Function(String)? onLog;
  final String? jobId;

  AdaptiveSpeedTester({required this.httpPort, this.onLog, this.jobId});

  Future<SpeedMetrics> runAdaptiveTest({
    Function(int current, int total, double speed)? onProgress,
    CancelToken? cancelToken,
  }) async {
    AdvancedLogger.info("Starting Adaptive Speed Test V2...");
    final overallStopwatch = Stopwatch()..start();

    try {
      // Stage 1: 100KB
      cancelToken?.throwIfCancelled();
      final s1 = await _testDownload(
        TestEndpoints.speedSmall.first, 
        onProgress: onProgress, 
        cancelToken: cancelToken
      );

      AdvancedLogger.info("Stage 1 (100KB) complete: ${s1.mbps.toStringAsFixed(2)} Mbps");
      
      if (s1.mbps <= 0.1) {
         AdvancedLogger.warn("Speed too low in Stage 1, skipping further stages.");
         return _buildMetrics(s1);
      }

      // Stage 2: 1MB
      cancelToken?.throwIfCancelled();
      AdvancedLogger.info("Proceeding to Stage 2 (1MB)...");
      final s2 = await _testDownload(
        TestEndpoints.speedMedium.first, 
        onProgress: onProgress, 
        cancelToken: cancelToken
      );

      AdvancedLogger.info("Stage 2 (1MB) complete: ${s2.mbps.toStringAsFixed(2)} Mbps");

      if (s2.mbps < 2.0) {
        return _buildMetrics(s2);
      }

      // Stage 3: 10MB
      cancelToken?.throwIfCancelled();
      AdvancedLogger.info("Proceeding to Stage 3 (10MB)...");
      final s3 = await _testDownload(
        TestEndpoints.speedLarge.first, 
        onProgress: onProgress, 
        cancelToken: cancelToken
      );

      AdvancedLogger.info("Stage 3 (10MB) complete: ${s3.mbps.toStringAsFixed(2)} Mbps");
      return _buildMetrics(s3);

    } on OperationCancelledException {
      AdvancedLogger.info("Speed test cancelled.");
      rethrow;
    } catch (e) {
      AdvancedLogger.error("Adaptive test error: $e");
      return SpeedMetrics(
        downloadMbps: 0,
        uploadMbps: 0,
        testFileUsed: "Error",
        downloadDuration: overallStopwatch.elapsed,
      );
    }
  }

  SpeedMetrics _buildMetrics(SpeedTestResult result) {
    return SpeedMetrics(
      downloadMbps: result.mbps,
      uploadMbps: 0,
      testFileUsed: "Adaptive (Best Phase)",
      downloadDuration: result.duration,
    );
  }

  Future<SpeedTestResult> _testDownload(String url, {
    Function(int current, int total, double speed)? onProgress,
    CancelToken? cancelToken,
  }) async {
    return TestTimeouts.withTimeout<SpeedTestResult>(
      _doDownload(url, onProgress, cancelToken),
      timeout: TestTimeouts.httpRequest,
      onTimeout: () => SpeedTestResult(0.0, "timeout", Duration.zero),
    );
  }

  Future<SpeedTestResult> _doDownload(String url, 
    Function(int current, int total, double speed)? onProgress,
    CancelToken? cancelToken,
  ) async {
    final client = HttpClient();
    if (jobId != null) CleanupUtils.registerResource(jobId!, client);
    
    client.findProxy = (uri) => "PROXY 127.0.0.1:$httpPort;";
    client.connectionTimeout = TestTimeouts.tcpHandshake;
    client.badCertificateCallback = (cert, host, port) => true;

    final stopwatch = Stopwatch();
    
    try {
      final request = await client.getUrl(Uri.parse(url));
      
      cancelToken?.addOnCancel(() {
        client.close(force: true);
      });

      final response = await request.close();
      
      if (response.statusCode != 200) {
        return SpeedTestResult(0.0, "error", Duration.zero);
      }

      int bytesReceived = 0;
      final contentLength = response.contentLength;
      int lastUpdateMs = 0;
      
      stopwatch.start();
      await for (var chunk in response) {
        if (cancelToken?.isCancelled == true) throw OperationCancelledException();
        
        bytesReceived += chunk.length;
        final elapsedMs = stopwatch.elapsedMilliseconds;

        if (elapsedMs - lastUpdateMs > 100) {
          final elapsedSec = elapsedMs / 1000;
          final currentMbps = elapsedSec > 0 ? (bytesReceived * 8) / (elapsedSec * 1024 * 1024) : 0.0;
          onProgress?.call(bytesReceived, contentLength > 0 ? contentLength : bytesReceived, currentMbps);
          lastUpdateMs = elapsedMs;
        }

        if (elapsedMs > 30000) break; // Safety limit per stage
      }
      
      stopwatch.stop();
      final totalSeconds = stopwatch.elapsed.inMicroseconds / 1000000.0;
      final mbps = totalSeconds > 0.1 ? (bytesReceived * 8) / (totalSeconds * 1024 * 1024) : 0.0;

      return SpeedTestResult(mbps, "success", stopwatch.elapsed);
    } catch (e) {
      if (e is! TimeoutException && e is! OperationCancelledException) {
         AdvancedLogger.error('Download Phase Error: $e');
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
