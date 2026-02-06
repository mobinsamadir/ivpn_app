import 'dart:io';
import '../utils/advanced_logger.dart';

class SpeedTestServiceDirect {
  Future<double> testDirectSpeed(String url) async {
    final client = HttpClient();
    final stopwatch = Stopwatch()..start();
    
    try {
      AdvancedLogger.info('[DirectTest] Starting test: $url');
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      
      int totalBytes = 0;
      await for (final chunk in response) {
        totalBytes += chunk.length;
        if (totalBytes % 100000 == 0) {
          AdvancedLogger.debug('[DirectTest] Received $totalBytes bytes...');
        }
      }
      
      stopwatch.stop();
      final elapsedSec = stopwatch.elapsedMilliseconds / 1000;
      final speedMbps = elapsedSec > 0 ? (totalBytes * 8) / (elapsedSec * 1000000) : 0.0;
      
      AdvancedLogger.info(
        '[DirectTest] Completed: ${speedMbps.toStringAsFixed(2)} Mbps',
        metadata: {
          'bytes': totalBytes,
          'ms': stopwatch.elapsedMilliseconds,
          'url': url,
        }
      );
      
      return speedMbps;
    } catch (e) {
      AdvancedLogger.error('[DirectTest] Failed: $e');
      return 0.0;
    } finally {
      client.close();
    }
  }
}
