import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Direct HTTP test without proxy', () async {
    final client = HttpClient();
    final stopwatch = Stopwatch()..start();
    
    try {
      print('Testing connection to httpbin.org...');
      final request = await client.getUrl(
        Uri.parse('https://httpbin.org/bytes/50000')
      );
      final response = await request.close();
      
      int totalBytes = 0;
      await for (final chunk in response) {
        totalBytes += chunk.length;
      }
      
      stopwatch.stop();
      final speedMbps = (totalBytes * 8) / 
                       (stopwatch.elapsedMilliseconds / 1000) / 
                       1000000;
      
      print('✅ SUCCESS: $totalBytes bytes in ${stopwatch.elapsedMilliseconds}ms');
      print('✅ Speed: ${speedMbps.toStringAsFixed(2)} Mbps');
      
      expect(totalBytes, greaterThan(0));
      expect(speedMbps, greaterThan(0));
    } catch (e) {
      print('❌ FAILED: $e');
      rethrow;
    } finally {
      client.close();
    }
  });
}
