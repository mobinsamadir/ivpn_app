import 'dart:async';
import 'dart:io';
import '../../utils/cancellable_operation.dart';
import '../../models/testing/test_results.dart';
import '../../utils/chart_utils.dart';
import '../../utils/test_constants.dart';
import '../../utils/cleanup_utils.dart';

class StabilityMonitor {
  final int httpPort;
  final Function(String)? onLog;
  final String? jobId;

  StabilityMonitor({required this.httpPort, this.onLog, this.jobId});

  Future<StabilityMetrics> monitorConnection({
    Duration duration = const Duration(seconds: 30),
    Duration interval = const Duration(milliseconds: 500),
    Function(int current, int total)? onProgress,
    Function(int latency)? onSample,
    CancelToken? cancelToken,
  }) async {
    final List<int> samples = [];
    int failureCount = 0;
    final startTime = DateTime.now();
    final totalSamples = (duration.inMilliseconds / interval.inMilliseconds).round();

    onLog?.call("📈 [STABILITY] Starting Stability Monitor (${duration.inSeconds}s, $totalSamples samples)...");

    for (int i = 0; i < totalSamples; i++) {
       if (cancelToken?.isCancelled == true) {
        onLog?.call("🛑 [STABILITY] Monitor cancelled.");
        break;
      }
      
      try {
        final latency = await _measureSinglePing(cancelToken: cancelToken);
        samples.add(latency);
        onSample?.call(latency);
        
        if (latency == -1) {
          failureCount++;
          onProgress?.call(i + 1, -1); // Report failure as per convention
        } else {
          onProgress?.call(i + 1, totalSamples);
          if (i % 5 == 0) {
            onLog?.call("📍 Sample $i: ${latency}ms");
          }
        }
      } catch (e) {
        failureCount++;
        samples.add(-1);
        onSample?.call(-1);
        onProgress?.call(i + 1, -1);
        onLog?.call("💥 [STABILITY] Sample error: $e");
      }

      await Future.delayed(interval);
    }

    final endTime = DateTime.now();
    final validSamples = samples.where((s) => s > 0).toList();
    
    final avgLatency = validSamples.isEmpty 
        ? 0.0 
        : validSamples.reduce((a, b) => a + b) / validSamples.length;
    
    final maxLatency = validSamples.isEmpty ? 0 : validSamples.reduce((a, b) => a > b ? a : b);
    final minLatency = validSamples.isEmpty ? 0 : validSamples.reduce((a, b) => a < b ? a : b);

    final metrics = StabilityMetrics(
      samples: samples,
      failureCount: failureCount,
      jitter: ChartUtils.calculateJitter(samples),
      packetLoss: (failureCount / totalSamples) * 100,
      averageLatency: avgLatency,
      maxLatency: maxLatency,
      minLatency: minLatency,
      standardDeviation: ChartUtils.calculateStandardDeviation(samples),
      startTime: startTime,
      endTime: endTime,
    );

    onLog?.call("📊 [STABILITY] Done. Jitter: ${metrics.jitter.toStringAsFixed(2)}ms, Loss: ${metrics.packetLoss.toStringAsFixed(1)}%");
    
    return metrics;
  }

  Future<int> _measureSinglePing({CancelToken? cancelToken}) async {
    return TestTimeouts.withTimeout<int>(
      _doSinglePing(cancelToken),
      timeout: TestTimeouts.pingCheck,
      onTimeout: () => -1,
    );
  }

  Future<int> _doSinglePing(CancelToken? cancelToken) async {
    final client = HttpClient();
    if (jobId != null) CleanupUtils.registerResource(jobId!, client);
    
    final stopwatch = Stopwatch();
    client.findProxy = (uri) => "PROXY 127.0.0.1:$httpPort;";
    client.connectionTimeout = TestTimeouts.tcpHandshake;
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      stopwatch.start();
      final request = await client.getUrl(Uri.parse("http://cp.cloudflare.com"));
      
      cancelToken?.addOnCancel(() {
        client.close(force: true);
      });

      final response = await request.close();
      stopwatch.stop();

      if (response.statusCode >= 200 && response.statusCode < 400) {
        return stopwatch.elapsedMilliseconds;
      } else {
        return -1;
      }
    } catch (e) {
      return -1;
    } finally {
      client.close(force: true);
    }
  }
}
