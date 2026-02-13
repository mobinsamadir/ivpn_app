import 'dart:async';
import '../utils/cancellable_operation.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/file_logger.dart';
import '../utils/test_constants.dart';
import 'windows_vpn_service.dart';
import 'singbox_config_generator.dart';
import '../models/testing/test_results.dart';
import 'testers/health_checker.dart';
import 'testers/stability_monitor.dart';
import 'testers/adaptive_speed_tester.dart';
import '../utils/cleanup_utils.dart';
import 'smart_pinger.dart';
import 'config_manager.dart'; // ✅ Added integration
import '../utils/advanced_logger.dart';
import 'dart:math';

class LatencyService {
  final WindowsVpnService _vpnService;
  static int _nextPort = 30000;

  LatencyService(this._vpnService);

  Future<void> _logToVlessFile(String message) async {
    try {
      final file = File('vless_debug.log');
      await file.writeAsString('${DateTime.now()}: $message\n', mode: FileMode.append);
    } catch (e) {
      print('Failed to write to vless log: $e');
    }
  }

  Future<int> getLatency(String rawConfig, {Function(String)? onLog}) async {
    final result = await getAdvancedLatency(rawConfig, onLog: onLog);
    return result.health.averageLatency;
  }

  Future<ServerTestResult> getAdvancedLatency(String rawConfig, {Function(String)? onLog, String? jobId, String? configId, bool isPriority = false, Duration? timeout}) async {
    return _measureRobust(
      rawConfig, 
      onLog, 
      jobId: jobId, 
      configId: configId, 
      timeout: timeout,
    );
  }

  Future<ServerTestResult> runStabilityTest(String rawConfig, {Function(String)? onLog, Function(int, int)? onProgress, Function(int)? onSample, CancelToken? cancelToken, String? jobId, String? configId, bool isPriority = true, Duration? timeout, Duration? duration}) async {
    return _measureRobust(
      rawConfig, 
      onLog, 
      isStabilityTest: true, 
      onProgress: onProgress, 
      onSample: onSample, 
      cancelToken: cancelToken, 
      jobId: jobId, 
      configId: configId, 
      timeout: timeout, 
      duration: duration
    );
  }

  Future<ServerTestResult> runSpeedTest(String rawConfig, {Function(String)? onLog, Function(int, int, double)? onProgress, CancelToken? cancelToken, String? jobId, String? configId, bool isPriority = true, Duration? timeout}) async {
    return _measureRobust(
      rawConfig, 
      onLog, 
      isSpeedTest: true, 
      onSpeedProgress: onProgress, 
      cancelToken: cancelToken, 
      jobId: jobId, 
      configId: configId, 
      timeout: timeout
    );
  }

  /// New batch testing method using SmartPinger
  Future<List<PingResult>> measureLatencies(List<String> configs, CancelToken? cancelToken) async {
    final results = <PingResult>[];
    
    for (final config in configs) {
      if (cancelToken?.isCancelled == true) break;
      
      try {
        final pingResult = await SmartPinger.pingMultiple(
          endpoints: [
            'https://1.1.1.1',
            'https://8.8.8.8',
            'https://dns.google',
          ],
          cancelToken: cancelToken,
          requiredSuccesses: 1,
        );
        
        results.add(PingResult(
          endpoint: "${config.substring(0, config.length > 30 ? 30 : config.length)}...",
          latency: pingResult.averageLatency.toInt(),
          isSuccess: pingResult.isOverallSuccess,
          error: pingResult.isOverallSuccess ? null : pingResult.recommendation,
        ));
      } catch (e) {
        results.add(PingResult(
          endpoint: "Error",
          latency: -1,
          isSuccess: false,
          error: e.toString(),
        ));
      }
    }
    return results;
  }

  Future<ServerTestResult> _measureRobust(
    String config, 
    Function(String)? onLog, {
    bool isStabilityTest = false,
    Function(int, int)? onProgress,
    Function(int)? onSample,
    bool isSpeedTest = false,
    Function(int, int, double)? onSpeedProgress,
    CancelToken? cancelToken,
    String? jobId,
    String? configId,
    Duration? timeout,
    Duration? duration,
  }) async {
    void log(String msg) {
       AdvancedLogger.info("[SERVICE] $msg");
       onLog?.call(msg);
    }

    // 1. TCP Pre-flight Check
    final serverDetails = SingboxConfigGenerator.extractServerDetails(config);
    if (serverDetails != null) {
      final host = serverDetails['host'] as String;
      final port = serverDetails['port'] as int;
      log("⚡ [PRE-FLIGHT] Checking $host:$port...");
      final tcpLatency = await _tcpPing(host, port);
      if (tcpLatency == -1) {
        log("❌ [PRE-FLIGHT] Server unreachable (TCP Handshake failed). Skipping core test.");
        return ServerTestResult.initial("unreachable");
      }
      log("✅ [PRE-FLIGHT] Port is open (${tcpLatency}ms).");
    }
    
    Process? process;
    File? configFile;
    final Completer<void> processExitCompleter = Completer<void>();
    
    final opTimeout = timeout ?? const Duration(seconds: 5);
    try {
      log("🔍 [INIT] Starting Robust Latency Test (Timeout: ${opTimeout.inSeconds}s)...");

      final int port = _nextPort;
      _nextPort += 2;
      if (_nextPort > 60000) _nextPort = 30000;

      final binPath = await _vpnService.getExecutablePath();
      final absoluteBinPath = p.isAbsolute(binPath) 
          ? binPath 
          : p.join(Directory.current.path, binPath);
      final binDir = p.dirname(absoluteBinPath);
      
      // Use generateConfig with isTest: true for lightweight execution
      final configJson = SingboxConfigGenerator.generateConfig(
        config, 
        listenPort: port,
        isTest: true,
      );
      
      final tempDir = await getTemporaryDirectory();
      configFile = File(p.join(tempDir.path, 'service_test_$port.json'));
      await configFile.writeAsString(configJson);

      if (!File(absoluteBinPath).existsSync()) {
         log("❌ [BIN] Binary NOT found at: $absoluteBinPath");
         return ServerTestResult.initial("missing_binary");
      }

      process = await Process.start(
        absoluteBinPath,
        ['run', '-c', configFile.path, '-D', '.'],
        workingDirectory: binDir,
        environment: {
          'ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS': 'true',
        },
      );

      cancelToken?.addOnCancel(() {
        process?.kill();
        log("🧹 [CANCEL] Process killed via token.");
      });
      
      log("📦 [PROCESS] Started (PID: ${process.pid}) on Port: $port");
      if (jobId != null) {
        CleanupUtils.registerResource(jobId, process);
      }

      final startCompleter = Completer<void>();

      process.stdout.transform(utf8.decoder).listen((data) {
          final line = data.trim();
          if (line.isEmpty) return;
          log("[CORE-OUT] $line");
          if (!startCompleter.isCompleted && (line.contains("started") || line.contains("inbound/http"))) {
              startCompleter.complete();
          }
      });

      process.stderr.transform(utf8.decoder).listen((data) {
           final line = data.trim();
           if (line.isEmpty) return;
           log("🚨 [CORE-ERR] $line");
           if (!startCompleter.isCompleted && (line.contains("started") || line.contains("inbound/http"))) {
               startCompleter.complete();
           }
      });

      process.exitCode.then((code) {
          log("🏁 [EXIT] Process ${process?.pid} exited with code $code");
          if (!startCompleter.isCompleted) {
              startCompleter.completeError("Crashed");
          }
          if (!processExitCompleter.isCompleted) {
              processExitCompleter.complete();
          }
      });

      try {
        // Startup should be fast, but cap it at opTimeout
        await startCompleter.future.timeout(opTimeout);
        log("✅ [READY] Core is running. Sending Ping...");
      } catch (e) {
        log("❌ [ABORT] Core failed to start: $e");
        return ServerTestResult.initial("core_failed");
      }

      // Probing starts here
      final client = HttpClient();
      client.findProxy = (uri) => "PROXY 127.0.0.1:${port + 1}";
      client.connectionTimeout = opTimeout;
      
      const String targetUrl = "http://cp.cloudflare.com";
      final sw = Stopwatch();
      
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          sw.reset();
          sw.start();
          log("Dart: 🚀 Sending request to $targetUrl via 127.0.0.1:${port + 1} (Attempt $attempt/2)");
          final request = await client.headUrl(Uri.parse(targetUrl)).timeout(opTimeout);
          final response = await request.close();
          sw.stop();
          log("Dart: 📩 Received response: ${response.statusCode}");
          
          if (response.statusCode == 502) {
            log("[SERVICE] ⚠️ Proxy Gateway Timeout (Server Unreachable)");
          }
          
          if (response.statusCode == 204 || response.statusCode == 200) {
            int lat = sw.elapsedMilliseconds;

            // SANITY CHECK: Impossible latency for real VPN
            // Only apply if it looks like a remote connection check
            if (lat < 10) {
                // Double check if target is local to avoid false positives on local dev tests
                bool isLocal = false;
                try {
                   final uri = Uri.parse(targetUrl);
                   if (uri.host == 'localhost' || uri.host == '127.0.0.1') isLocal = true;
                } catch(_) {}

                if (!isLocal) {
                   log("⚠️ [PROBE] Latency too low (${lat}ms). Possible process crash or loopback.");

                   // RETRY LOGIC for false positive
                   if (attempt < 2) {
                      log("🔄 [RETRY] Waiting 500ms and retrying to confirm latency...");
                      await Future.delayed(const Duration(milliseconds: 500));
                      continue; // Proceed to next attempt loop
                   } else {
                      log("❌ [FAIL] Persistently low latency. Marking as failure.");
                      throw const SocketException("False positive: Latency < 10ms");
                   }
                }
            }

            final healthMetrics = HealthMetrics(
              endpointLatencies: {targetUrl: lat},
              successRate: 100.0,
              averageLatency: lat,
              dnsWorking: true,
            );

            if (configId != null) {
              await ConfigManager().updateConfigMetrics(configId, ping: lat);
            }

            // Simple latency test: return now
            if (!isStabilityTest && !isSpeedTest) {
              return ServerTestResult(
                serverId: config.hashCode.toString(),
                health: healthMetrics,
                finalScore: (100 - (lat / 30)).clamp(0, 100).toDouble(),
                testTime: DateTime.now(),
              );
            }

            // Stability test
            if (isStabilityTest) {
              final stabilityMonitor = StabilityMonitor(httpPort: port + 1, onLog: onLog, jobId: jobId);
              final stabilityMetrics = await stabilityMonitor.monitorConnection(
                onProgress: onProgress, 
                onSample: onSample, 
                cancelToken: cancelToken,
                duration: duration ?? const Duration(seconds: 30),
              );
              return ServerTestResult(
                serverId: config.hashCode.toString(),
                health: healthMetrics,
                stability: stabilityMetrics,
                finalScore: (100 - (lat / 30)).clamp(0, 100) * 0.4 + (100 - stabilityMetrics.packetLoss * 10) * 0.6,
                testTime: DateTime.now(),
              );
            }

            // Speed test
            if (isSpeedTest) {
              final speedTester = AdaptiveSpeedTester(httpPort: port + 1, onLog: onLog, jobId: jobId);
              final speedMetrics = await speedTester.runAdaptiveTest(onProgress: onSpeedProgress, cancelToken: cancelToken);
              if (configId != null) {
                await ConfigManager().updateConfigMetrics(configId, speed: speedMetrics.downloadMbps);
              }
              return ServerTestResult(
                serverId: config.hashCode.toString(),
                health: healthMetrics,
                speed: speedMetrics,
                finalScore: (100 - (lat / 30)).clamp(0, 100) * 0.3 + (speedMetrics.downloadMbps > 50 ? 50 : speedMetrics.downloadMbps) * 0.7 + 20,
                testTime: DateTime.now(),
              );
            }
          }
          
          // Successful request but not 200/204 (e.g. 502/403) - stop retrying
          if (response.statusCode == 502 || response.statusCode == 403) break;

        } catch (e) {
          log("💥 [PROBE] Attempt $attempt failed: $e");
          if (attempt < 2) {
            log("[SERVICE] ⚠️ Retrying in 1s...");
            await Future.delayed(const Duration(seconds: 1));
            sw.reset();
            sw.start();
          } else {
            // All attempts failed
          }
        }
      }

      return ServerTestResult.initial("no_response");

    } catch (e) {
      log("💥 [EXCEPTION] Service Error: $e");
      return ServerTestResult.initial("error");
    } finally {
      if (process != null) {
          log("🧹 [CLEANUP] Killing PID ${process.pid}...");
          process.kill();
          if (Platform.isWindows) {
              Process.run('taskkill', ['/F', '/PID', '${process.pid}']);
          }
          try {
             await processExitCompleter.future.timeout(const Duration(seconds: 1));
          } catch (_) {}
      }

      if (configFile != null && await configFile.exists()) {
          try { await configFile.delete(); } catch (_) {}
      }
    }
  }

  Future<int> _tcpPing(String host, int port) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
      socket.destroy();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      return -1;
    }
  }

  Future<int> _getEphemeralPort() async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    } catch (e) {
      return 0;
    }
  }
  
  Future<bool> _isPortAvailable(int port) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 500));
      socket.destroy();
      return false; 
    } catch (e) {
      return true; 
    }
  }

  // --- Real Speed Test ---
  Future<double> getDownloadSpeed(String config) async {
    Process? process;
    File? configFile;
    int port = 0;

    try {
      // 1. Setup Port & Sing-box
      port = _nextPort;
      _nextPort += 2;
      if (_nextPort > 60000) _nextPort = 30000;

      final binPath = await _vpnService.getExecutablePath();
      final absoluteBinPath = p.isAbsolute(binPath) ? binPath : p.join(Directory.current.path, binPath);
      final binDir = p.dirname(absoluteBinPath);
      
      final configJson = SingboxConfigGenerator.generateConfig(config, listenPort: port, isTest: true);
      final tempDir = await getTemporaryDirectory();
      configFile = File(p.join(tempDir.path, 'speed_test_$port.json'));
      await configFile.writeAsString(configJson);

      if (!File(absoluteBinPath).existsSync()) return 0.0;

      process = await Process.start(
        absoluteBinPath,
        ['run', '-c', configFile.path, '-D', '.'],
        workingDirectory: binDir,
        environment: {
          'ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS': 'true',
        },
      );

      final Completer<void> startCompleter = Completer<void>();
      process.stdout.transform(utf8.decoder).listen((data) {
          if (!startCompleter.isCompleted && (data.contains("started") || data.contains("inbound/http"))) {
              startCompleter.complete();
          }
      });
      process.stderr.transform(utf8.decoder).listen((data) {
           if (!startCompleter.isCompleted && (data.contains("started") || data.contains("inbound/http"))) {
              startCompleter.complete();
          }
      });

      // Wait for start (max 5s)
      try {
        await startCompleter.future.timeout(const Duration(seconds: 5));
      } catch (e) {
        return 0.0;
      }

      // 2. Perform Download Test
      final client = HttpClient();
      client.findProxy = (uri) => "PROXY 127.0.0.1:${port + 1}";
      client.connectionTimeout = const Duration(seconds: 10);
      
      final sw = Stopwatch();
      int bytesReceived = 0;
      
      try {
        sw.start();
        final request = await client.getUrl(Uri.parse("https://speed.cloudflare.com/__down?bytes=1000000"))
            .timeout(const Duration(seconds: 15));
        final response = await request.close();
        
        await response.listen((chunk) {
          bytesReceived += chunk.length;
        }).asFuture().timeout(const Duration(seconds: 15));
        
        sw.stop();
        
        // 3. Calculate Speed
        if (sw.elapsedMilliseconds == 0) return 0.0;
        
        final double bits = bytesReceived * 8.0;
        final double seconds = sw.elapsedMilliseconds / 1000.0;
        final double mbps = (bits / seconds) / 1000000.0;
        
        return double.parse(mbps.toStringAsFixed(2));

      } catch (e) {
        AdvancedLogger.error("❌ Speed Test Failed: $e");
        return 0.0;
      }

    } catch (e) {
      AdvancedLogger.error("❌ Speed Test Setup Error: $e");
      return 0.0;
    } finally {
      process?.kill();
      if (Platform.isWindows && process != null) {
          try { Process.run('taskkill', ['/F', '/PID', '${process.pid}']); } catch (_) {}
      }
      try { if (configFile != null && await configFile.exists()) await configFile.delete(); } catch (_) {}
    }
  }
}
