import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/vpn_config_with_metrics.dart';
import '../singbox_config_generator.dart';
import '../../utils/advanced_logger.dart';
import '../../utils/port_allocator.dart'; // NEW
import '../binary_manager.dart';
import '../native_vpn_service.dart';

/// Test Modes
/// - `connectivity`: Stages 1 (TCP) & 2 (HTTP) only. Used for validation.
/// - `speed`: Stages 1, 2, & 3 (Download). Used for ranking.
enum TestMode { connectivity, speed }

// Top-level function for compute
String _generateConfigWrapper(Map<String, dynamic> args) {
  return SingboxConfigGenerator.generateConfig(
    args['rawConfig'],
    listenPort: args['listenPort'],
    isTest: args['isTest'],
  );
}

/// Semaphore to limit concurrent operations
class Semaphore {
  final int max;
  int _current = 0;
  final List<Completer> _waitQueue = [];

  Semaphore(this.max);

  Future<void> acquire() async {
    if (_current < max) {
      _current++;
      return;
    }
    final completer = Completer();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    } else {
      _current--;
    }
  }
}

class EphemeralTester {
  static final EphemeralTester _instance = EphemeralTester._internal();
  factory EphemeralTester() => _instance;
  EphemeralTester._internal();

  // Limit Windows concurrent processes to 5 to prevent UI freeze
  static final Semaphore _windowsSemaphore = Semaphore(5);

  // STRICTLY Serialize Android Libbox Calls (Concurrency = 1)
  static final Semaphore _androidSemaphore = Semaphore(1);

  // Track active processes to kill on exit
  static final List<Process> _activeProcesses = [];

  /// Registers a process to be killed later
  static void registerProcess(Process p) {
    _activeProcesses.add(p);
  }

  /// Kills all registered processes (Windows only)
  static void killAll() {
    if (!Platform.isWindows) return; // Safety check
    AdvancedLogger.info(
        "EphemeralTester: Killing all ${_activeProcesses.length} active processes...");
    for (var p in _activeProcesses) {
      try {
        p.kill(ProcessSignal.sigkill);
      } catch (e) {
        AdvancedLogger.warn("Failed to kill process: $e");
      }
    }
    _activeProcesses.clear();
  }

  /// Helper to extract host/port using the robust generator logic
  Map<String, dynamic>? _extractHostPort(String config) {
    return SingboxConfigGenerator.extractServerDetails(config);
  }

  /// Runs the Funnel Test on a specific config based on the mode.
  /// Returns a VpnConfigWithMetrics object with updated stageResults and scores.
  Future<VpnConfigWithMetrics> runTest(VpnConfigWithMetrics config,
      {TestMode mode = TestMode.speed}) async {
    // --- ANDROID PATH (STRICT SERIALIZATION FOR STAGE 2/3) ---
    if (Platform.isAndroid) {
      // STAGE 1: TCP Check (Concurrent - No Semaphore)
      try {
        final details = _extractHostPort(config.rawConfig);
        if (details == null) {
          throw Exception("Could not extract server details");
        }

        final String host = details['host'];
        final int port = details['port'];

        Socket? socket;
        try {
          socket = await Socket.connect(host, port,
              timeout: const Duration(seconds: 3));
          socket.destroy();
        } catch (e) {
          throw Exception("Stage 1 (TCP) Failed: $e");
        }
      } catch (e) {
        // Fail fast on TCP
        return config.copyWith(
          funnelStage: 0,
          failureReason: "Stage 1 Failed: $e",
          lastFailedStage: "Stage1_TCP",
          failureCount: config.failureCount + 1,
          lastTestedAt: DateTime.now(),
          ping: -1,
        );
      }

      // STAGE 2 & 3: Native Proxy (Serialized)
      await _androidSemaphore.acquire();

      final nativeService = NativeVpnService();
      int proxyPort = -1;
      int latency = 0;
      double speedMbps = 0.0;
      bool stage2Success = false;
      bool stage3Success = false;
      String? errorMsg;

      try {
        // Generate Test Config (isTest=true for lighter routing)
        // We pass listenPort=0 as Android ignores it and assigns random, but generator needs int
        final jsonConfig = await compute(_generateConfigWrapper, {
          'rawConfig': config.rawConfig,
          'listenPort': 10808,
          'isTest': true,
        });

        // Start Proxy
        proxyPort = await nativeService.startTestProxy(jsonConfig);

        if (proxyPort <= 0) {
          throw Exception(
              "Failed to start Native Test Proxy (Code: $proxyPort)");
        }

        // Setup HttpClient with SOCKS Proxy
        final client = HttpClient();

        try {
          client.findProxy = (uri) => "SOCKS5 127.0.0.1:$proxyPort";
          client.connectionTimeout = const Duration(seconds: 5);

          // Test HTTP (Stage 2)
          final sw = Stopwatch()..start();
          try {
            final req = await client
                .getUrl(Uri.parse('https://www.google.com/generate_204'));
            final resp = await req.close();
            sw.stop();

            if (resp.statusCode == 204) {
              latency = sw.elapsedMilliseconds;
              stage2Success = true;
            } else {
              throw Exception("HTTP Status ${resp.statusCode}");
            }
          } catch (e) {
            throw Exception("Stage 2 (HTTP) Failed: $e");
          }

          // Test Speed (Stage 3) - Only if requested and Stage 2 passed
          if (mode == TestMode.speed && stage2Success) {
            int bytes = 0;
            final speedSw = Stopwatch();
            try {
              speedSw.start();
              // Download ~1MB test file
              final speedReq = await client.getUrl(
                  Uri.parse('http://speed.cloudflare.com/__down?bytes=1000000'));
              final speedResp = await speedReq.close();

              await speedResp.listen((chunk) {
                bytes += chunk.length;
              }).asFuture().timeout(const Duration(seconds: 5));

              speedSw.stop();
              final durationSec = speedSw.elapsedMilliseconds / 1000.0;
              if (durationSec > 0 && bytes > 0) {
                speedMbps = (bytes * 8) / (durationSec * 1000000); // Mbps
                stage3Success = true;
              }
            } catch (e) {
              AdvancedLogger.warn("Stage 3 (Speed) Failed: $e");
              // Don't fail the whole config if speed test fails, just mark speed 0
            }
          }
        } finally {
          // FIX: Ensure client is closed to prevent socket leak
          client.close();
        }
      } catch (e) {
        errorMsg = e.toString();
      } finally {
        await nativeService.stopTestProxy();
        _androidSemaphore.release();
      }

      if (errorMsg != null) {
        return config.copyWith(
          funnelStage: 0,
          failureReason: errorMsg,
          lastFailedStage: stage2Success ? "Stage3_Speed" : "Stage2_HTTP",
          failureCount: config.failureCount + 1,
          lastTestedAt: DateTime.now(),
          ping: -1,
        );
      }

      // Success
      int score = 0;
      if (speedMbps > 0) score += (speedMbps * 5).clamp(0, 50).toInt();
      if (latency > 0) score += (1000 ~/ latency).clamp(0, 50).toInt();

      final newStageResults = Map<String, TestResult>.from(config.stageResults);
      newStageResults['TCP'] = TestResult(success: true);
      newStageResults['HTTP'] = TestResult(success: true, latency: latency);
      if (stage3Success) {
        newStageResults['Speed'] = TestResult(success: true, latency: 0);
      }

      return config.copyWith(
          funnelStage: stage3Success ? 3 : 2,
          speedScore: score,
          stageResults: newStageResults,
          failureCount: 0,
          isAlive: true,
          lastTestedAt: DateTime.now(),
          lastSuccessfulConnectionTime: DateTime.now().millisecondsSinceEpoch,
          deviceMetrics: config
              .updateMetrics(
                  deviceId: "android_verified",
                  ping: latency,
                  speed: speedMbps)
              .deviceMetrics);
    } else {
      // --- WINDOWS / DESKTOP PATH ---
      // Acquire Semaphore
      await _windowsSemaphore.acquire();

      int port = 0;
      Process? process;
      File? tempConfigFile;
      final dartHttpClient = HttpClient();

      // Results containers
      bool stage1Success = false;
      bool stage2Success = false;
      double speedMbps = 0.0;
      int latency = 0;

      try {
        // Use Port Allocator
        port = await PortAllocator().allocate();

        final testId = DateTime.now().millisecondsSinceEpoch;

        // 1. Prepare Config (JSON)
        // FIX: EnsureBinary is strictly bypassed on Android via the if/else wrapper
        final binPath = await BinaryManager.ensureBinary();
        final tempDir = await getTemporaryDirectory();
        tempConfigFile =
            File(p.join(tempDir.path, 'test_${config.id}_$testId.json'));

        final jsonConfig = await compute(_generateConfigWrapper, {
          'rawConfig': config.rawConfig,
          'listenPort': port,
          'isTest': true,
        });

        final Map<String, dynamic> parsedJson = jsonDecode(jsonConfig);

        parsedJson['log'] = {
          "level": "fatal",
          "output": "stderr",
          "timestamp": true
        };

        if (parsedJson['inbounds'] is List) {
          for (var inbound in parsedJson['inbounds']) {
            inbound['listen'] = "127.0.0.1";
          }
        }

        await tempConfigFile.writeAsString(jsonEncode(parsedJson));

        // 2. Spawn Process
        await Future.delayed(Duration.zero);

        final processFuture = Process.start(
          binPath,
          ['run', '-c', tempConfigFile.path],
          runInShell: false,
          workingDirectory: p.dirname(binPath),
          environment: {'ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS': 'true'},
        );

        process = await processFuture.timeout(const Duration(seconds: 5),
            onTimeout: () {
          throw TimeoutException("Process spawn timed out");
        });

        registerProcess(process);

        await Future.delayed(const Duration(milliseconds: 500));

        dartHttpClient.findProxy = (uri) => "PROXY 127.0.0.1:${port + 1}";
        dartHttpClient.connectionTimeout = const Duration(seconds: 5);

        // --- STAGE 1 (TCP) ---
        int attempts = 0;
        while (attempts < 3) {
          try {
            final socket = await Socket.connect('127.0.0.1', port,
                timeout: const Duration(milliseconds: 1500));
            socket.destroy();
            stage1Success = true;
            break;
          } catch (e) {
            attempts++;
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }

        if (!stage1Success) throw Exception("Local Proxy failed to start");

        // --- STAGE 2 (HTTP) ---
        final sw = Stopwatch()..start();
        try {
          final req = await dartHttpClient
              .getUrl(Uri.parse('https://www.google.com/generate_204'));
          final resp = await req.close();
          sw.stop();

          if (resp.statusCode == 204) {
            latency = sw.elapsedMilliseconds;
            stage2Success = true;
          } else {
            throw Exception("Status ${resp.statusCode}");
          }
        } catch (e) {
          throw Exception("Stage 2 Failed: $e");
        }

        // --- STAGE 3 (Speed) ---
        if (mode == TestMode.speed) {
          int bytes = 0;
          final speedSw = Stopwatch();

          try {
            speedSw.start();
            final speedReq = await dartHttpClient.getUrl(
                Uri.parse('http://speed.cloudflare.com/__down?bytes=1000000'));
            final speedResp = await speedReq.close();

            await speedResp.listen((chunk) {
              bytes += chunk.length;
            }).asFuture().timeout(const Duration(seconds: 5));

            speedSw.stop();

            final durationSec = speedSw.elapsedMilliseconds / 1000.0;
            if (durationSec > 0 && bytes > 0) {
              speedMbps = (bytes * 8) / (durationSec * 1000000);
            }
          } catch (e) {
            AdvancedLogger.warn("Stage 3 (Speed) failed/timed out: $e");
          }
        }

        // Success Logic
        int score = 0;
        if (speedMbps > 0) score += (speedMbps * 5).clamp(0, 50).toInt();
        if (latency > 0) score += (1000 ~/ latency).clamp(0, 50).toInt();

        final finalStage = (speedMbps > 0) ? 3 : 2;
        final newStageResults =
            Map<String, TestResult>.from(config.stageResults);
        newStageResults['TCP'] = TestResult(success: true);
        newStageResults['HTTP'] = TestResult(success: true, latency: latency);
        if (speedMbps > 0) {
          newStageResults['Speed'] = TestResult(success: true, latency: 0);
        }

        return config.copyWith(
            funnelStage: finalStage,
            speedScore: score,
            stageResults: newStageResults,
            failureCount: 0,
            isAlive: true,
            lastTestedAt: DateTime.now(),
            lastSuccessfulConnectionTime: DateTime.now().millisecondsSinceEpoch,
            deviceMetrics: config
                .updateMetrics(
                    deviceId: "windows_ephemeral",
                    ping: latency,
                    speed: speedMbps)
                .deviceMetrics);
      } catch (e) {
        AdvancedLogger.warn("EphemeralTester Error (${config.name}): $e");

        String failedStage = "Init";
        if (!stage1Success) {
          failedStage = "Stage1_ProxyInit";
        } else if (!stage2Success) {
          failedStage = "Stage2_HTTP";
        } else {
          failedStage = "Stage3_Speed";
        }

        return config.copyWith(
          funnelStage: 0,
          failureReason: e.toString(),
          lastFailedStage: failedStage,
          failureCount: config.failureCount + 1,
          lastTestedAt: DateTime.now(),
          ping: -1,
        );
      } finally {
        dartHttpClient.close();
        try {
          if (process != null) {
            process.kill(ProcessSignal.sigkill);
            _activeProcesses.remove(process);
          }
        } catch (e) {
          AdvancedLogger.warn("EphemeralTester: Error killing process: $e");
        }
        try {
          if (tempConfigFile != null && await tempConfigFile.exists()) {
            await tempConfigFile.delete();
          }
        } catch (_) {}

        // Release Port & Semaphore
        if (port > 0) PortAllocator().release(port);
        _windowsSemaphore.release();
      }
    }
  }
}
