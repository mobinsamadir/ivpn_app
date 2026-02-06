// lib/services/speed_test_service.dart

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../utils/advanced_logger.dart';

class SpeedTestService {
  final Dio _dio;
  
  // HTTP-only URLs that work through HTTP proxy (no HTTPS!)
  static const List<String> _testUrls = [
    'http://speedtest.tele2.net/10MB.zip',
    'http://ipv4.download.thinkbroadband.com/10MB.zip',
    'http://proof.ovh.net/files/10Mb.dat',
  ];
  static const double _fileSizeInMegabits = 10.0 * 8; // 80 Mbit

  SpeedTestService({Dio? dio}) : _dio = dio ?? Dio() {
    AdvancedLogger.debug('SpeedTestService initialized');
  }

  /// Configure proxy for VPN tunnel (CRITICAL for speed test to work)
  void configureProxy(String proxyHost, int proxyPort) {
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.findProxy = (uri) {
        final proxy = 'PROXY $proxyHost:$proxyPort';
        AdvancedLogger.debug('Configuring proxy for $uri', metadata: {'proxy': proxy});
        return proxy;
      };
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
    AdvancedLogger.info('Proxy configured: $proxyHost:$proxyPort');
  }

  /// Verify network connectivity before test
  Future<bool> _verifyConnectivity() async {
    try {
      AdvancedLogger.debug('Verifying network connectivity...');
      final result = await InternetAddress.lookup('google.com');
      final isConnected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      AdvancedLogger.info('Network connectivity: ${isConnected ? "OK" : "FAILED"}');
      return isConnected;
    } catch (e) {
      AdvancedLogger.error('Network connectivity check failed', error: e);
      return false;
    }
  }

  /// Tests the download speed and returns the result in Mbps.
  /// Returns 0.0 on failure.
  Future<double> testDownloadSpeed() async {
    AdvancedLogger.info('===== SPEED TEST STARTED =====');
    
    // Verify connectivity first
    if (!await _verifyConnectivity()) {
      AdvancedLogger.error('Speed test aborted: No network connectivity');
      return 0.0;
    }

    // Try each URL until one succeeds
    for (final url in _testUrls) {
      try {
        AdvancedLogger.info('Attempting speed test with: $url');
        final speed = await _performSpeedTest(url);
        if (speed > 0) {
          AdvancedLogger.info('===== SPEED TEST COMPLETED: ${speed.toStringAsFixed(2)} Mbps =====');
          return speed;
        }
      } catch (e, stackTrace) {
        AdvancedLogger.error('Speed test failed for $url', error: e, stackTrace: stackTrace);
        continue; // Try next URL
      }
    }
    
    AdvancedLogger.error('All speed test URLs failed');
    return 0.0;
  }

  /// Perform actual speed test
  Future<double> _performSpeedTest(String url) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      AdvancedLogger.networkRequest('GET', url);
      
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          maxRedirects: 5,
        ),
      );
      
      stopwatch.stop();
      final durationInSeconds = stopwatch.elapsed.inMilliseconds / 1000.0;
      
      AdvancedLogger.networkResponse(
        url,
        response.statusCode ?? 0,
        duration: stopwatch.elapsed,
        body: {'bytesReceived': response.data?.length ?? 0},
      );
      
      if (durationInSeconds == 0) {
        AdvancedLogger.warn('Speed test duration is 0 - invalid timing');
        return 0.0;
      }

      final speedMbps = _fileSizeInMegabits / durationInSeconds;
      AdvancedLogger.info(
        'Speed calculated: ${speedMbps.toStringAsFixed(2)} Mbps',
        metadata: {
          'durationSec': durationInSeconds,
          'fileSizeMbits': _fileSizeInMegabits,
          'bytesReceived': response.data?.length ?? 0,
        },
      );
      
      return speedMbps;
    } catch (e, stackTrace) {
      stopwatch.stop();
      AdvancedLogger.error(
        'Speed test error for $url',
        error: e,
        stackTrace: stackTrace,
        metadata: {'elapsedMs': stopwatch.elapsedMilliseconds},
      );
      return 0.0;
    }
  }
}
