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

// Top-level function for compute to extract server details
Map<String, dynamic>? _extractHostPortWrapper(String config) {
  return SingboxConfigGenerator.extractServerDetails(config);
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
      final next = _waitQueue.removeAt(0);
      if (!next.isCompleted) next.complete();
    } else {
      if (_current > 0) _current--;
    }
  }
}

class EphemeralTester {
  static final EphemeralTester _instance = EphemeralTester._internal();
  factory EphemeralTester() => _instance;
  EphemeralTester._internal();

  // Limit Windows concurrent processes to 5 to prevent UI freeze
  // Limit Windows concurrent processes to prevent UI freeze and port collision
  static final Semaphore _windowsSemaphore = Semaphore(2);

  // Android Concurrency = 3 (Safe for Modern Devices)
  static final Semaphore _androidSemaphore = Semaphore(3);

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
      "EphemeralTester: Killing all ${_activeProcesses.length} active processes...",
    );
    for (var p in _activeProcesses) {
      try {
        p.kill(ProcessSignal.sigkill);
      } catch (e) {
        AdvancedLogger.warn("Failed to kill process: $e");
      }
    }
    _activeProcesses.clear();
  }

  /// Runs the Funnel Test on a specific config based on the mode.
  /// Returns a VpnConfigWithMetrics object with updated stageResults and scores.
  Future<VpnConfigWithMetrics> runTest(
    VpnConfigWithMetrics config, {
    TestMode mode = TestMode.speed,
  }) async {
    final completer = Completer<VpnConfigWithMetrics>();

    // Variables for Watchdog Cleanup
    Process? processForCleanup;
    bool isCompleted = false;

    // Watchdog Timer
    final timer = Timer(const Duration(seconds: 15), () {
      if (!isCompleted) {
        isCompleted = true;
        AdvancedLogger.warn(
          "[EphemeralTester] WATCHDOG TRIGGERED for ${config.name}. Force killing process...",
        );

        if (processForCleanup != null) {
          try {
            processForCleanup?.kill(ProcessSignal.sigkill);
          } catch (_) {}
          _activeProcesses.remove(processForCleanup);
        } else if (Platform.isAndroid) {
          try {
            NativeVpnService().stopTestProxy();
          } catch (_) {}
        }

        if (!completer.isCompleted) {
          completer.complete(
            config.copyWith(
              funnelStage: 0,
              failureReason: "Strict Watchdog Timeout",
              lastFailedStage: "Watchdog_Timeout",
              failureCount: config.failureCount + 1,
              lastTestedAt: DateTime.now(),
              ping: -1,
            ),
          );
        }
      }
    });

    void setProcess(Process? p) => processForCleanup = p;
    void setPort(
      int p,
    ) {} // Not needed here anymore, runTestInternal handles port

    _runTestInternal(config, mode, setProcess, setPort).then((result) {
      if (!isCompleted) {
        isCompleted = true;
        timer.cancel();
        if (!completer.isCompleted) completer.complete(result);
      }
    }).catchError((e) {
      if (!isCompleted) {
        isCompleted = true;
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete(
            config.copyWith(
              funnelStage: 0,
              failureReason: "Test Error: $e",
              lastFailedStage: "Error",
              failureCount: config.failureCount + 1,
              lastTestedAt: DateTime.now(),
              ping: -1,
            ),
          );
        }
      }
    });

    return completer.future;
  }

  Future<VpnConfigWithMetrics> _runTestInternal(
    VpnConfigWithMetrics config,
    TestMode mode,
    Function(Process?) onProcess,
    Function(int) onPort,
  ) async {
    // --- ANDROID PATH (STRICT SERIALIZATION FOR STAGE 2/3) ---
    if (Platform.isAndroid) {
      // STAGE 1: TCP Check (Concurrent - No Semaphore)
      try {
        // Offload parsing to Isolate
        final details = await compute(
          _extractHostPortWrapper,
          config.rawConfig,
        );
        if (details == null)
          throw Exception("Could not extract server details");

        final String host = details['host'];
        final int port = details['port'];

        Socket? socket;
        try {
          socket = await Socket.connect(
            host,
            port,
            timeout: const Duration(seconds: 3),
          );
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
      int listenPort = 0; // NEW: Dynamic Port Allocation
      int latency = 0;
      double speedMbps = 0.0;
      bool stage2Success = false;
      bool stage3Success = false;
      String? errorMsg;

      try {
        // Allocate dynamic port
        listenPort = await PortAllocator().allocate();
        if (listenPort <= 0) {
          throw Exception("Port Allocator returned invalid port: $listenPort");
        }
        AdvancedLogger.warn('[TESTER] Initializing on Port: $listenPort');
        onPort(listenPort); // Register for watchdog

        // Generate Test Config
        final jsonConfig = await compute(_generateConfigWrapper, {
          'rawConfig': config.rawConfig,
          'listenPort': listenPort,
          'isTest': true,
        });

        // Start Proxy
        try {
          proxyPort = await nativeService.startTestProxy(jsonConfig);
        } catch (e) {
          proxyPort = -1;
          AdvancedLogger.error("Native Start Exception: $e");
        }

        AdvancedLogger.warn(
          '[TESTER] Native Process Spawned (via Service). Port: $proxyPort',
        );

        if (proxyPort <= 0) {
          throw Exception("Early Exit: Native Proxy Failed (Code: $proxyPort)");
        }

        AdvancedLogger.warn(
          '[TESTER] Waiting for local socket to become ready...',
        );

        // Setup HttpClient
        final client = HttpClient();

        try {
          // Constraint 3: Isolated SSL Bypass
          client.badCertificateCallback = (cert, host, port) => true;

          client.findProxy = (uri) => "SOCKS5 127.0.0.1:$proxyPort";
          client.connectionTimeout = const Duration(seconds: 5);

          // Test HTTP (Stage 2) with Retry for HandshakeException
          // Delay briefly to allow sing-box to establish upstream TLS
          await Future.delayed(const Duration(milliseconds: 500));

          final sw = Stopwatch()..start();
          int httpAttempts = 0;

          while (httpAttempts < 2) {
            try {
              AdvancedLogger.warn(
                '[TESTER] HTTP Probe started to http://127.0.0.1:$proxyPort (Attempt ${httpAttempts + 1})',
              );
              final req = await client.getUrl(
                Uri.parse('https://www.google.com/generate_204'),
              );
              final resp =
                  await req.close().timeout(const Duration(seconds: 5));
              sw.stop();

              AdvancedLogger.warn(
                '[TESTER] HTTP Response received: ${resp.statusCode}',
              );

              if (resp.statusCode == 204) {
                latency = sw.elapsedMilliseconds;
                stage2Success = true;
                break;
              } else {
                throw Exception("HTTP Status ${resp.statusCode}");
              }
            } catch (e) {
              httpAttempts++;
              if (httpAttempts < 2 &&
                  (e.toString().contains('HandshakeException') ||
                      e.toString().contains('SocketException'))) {
                AdvancedLogger.warn(
                    '[TESTER] HTTP Handshake failed, retrying in 1s... $e');
                await Future.delayed(const Duration(seconds: 1));
              } else {
                AdvancedLogger.warn('[TESTER] HTTP Response Error: $e');
                throw Exception("Stage 2 (HTTP) Failed: $e");
              }
            }
          }

          // Test Speed (Stage 3)
          if (mode == TestMode.speed && stage2Success) {
            int bytes = 0;
            final speedSw = Stopwatch();
            try {
              speedSw.start();
              final speedReq = await client.getUrl(
                Uri.parse('https://speed.cloudflare.com/__down?bytes=1000000'),
              );
              final speedResp = await speedReq.close();

              await speedResp
                  .listen((chunk) {
                    bytes += chunk.length;
                  })
                  .asFuture()
                  .timeout(const Duration(seconds: 5));

              speedSw.stop();
              final durationSec = speedSw.elapsedMilliseconds / 1000.0;
              if (durationSec > 0 && bytes > 0) {
                speedMbps = (bytes * 8) / (durationSec * 1000000); // Mbps
                stage3Success = true;
              }
            } catch (e) {
              AdvancedLogger.warn("Stage 3 (Speed) Failed: $e");
            }
          }
        } finally {
          client.close();
        }
      } catch (e) {
        errorMsg = e.toString();
      } finally {
        await nativeService.stopTestProxy();
        if (listenPort > 0) PortAllocator().release(listenPort);
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
              speed: speedMbps,
            )
            .deviceMetrics,
      );
    } else {
      // --- WINDOWS / DESKTOP PATH ---
      await _windowsSemaphore.acquire();

      int port = 0;
      Process? process;
      File? tempConfigFile;
      final dartHttpClient = HttpClient();
      // Constraint 3: Isolated SSL Bypass
      dartHttpClient.badCertificateCallback = (cert, host, port) => true;

      bool stage1Success = false;
      bool stage2Success = false;
      double speedMbps = 0.0;
      int latency = 0;

      try {
        port = await PortAllocator().allocate();
        AdvancedLogger.warn('[TESTER] Initializing on Port: $port');
        onPort(port); // Register for watchdog

        final testId = DateTime.now().millisecondsSinceEpoch;

        final binPath = await BinaryManager.ensureBinary();
        final tempDir = await getTemporaryDirectory();
        tempConfigFile = File(
          p.join(tempDir.path, 'test_${config.id}_$testId.json'),
        );

        final jsonConfig = await compute(_generateConfigWrapper, {
          'rawConfig': config.rawConfig,
          'listenPort': port,
          'isTest': true,
        });

        final Map<String, dynamic> parsedJson = jsonDecode(jsonConfig);
        parsedJson['log'] = {
          "level": "fatal",
          "output": "stderr",
          "timestamp": true,
        };
        if (parsedJson['inbounds'] is List) {
          for (var inbound in parsedJson['inbounds']) {
            inbound['listen'] = "127.0.0.1";
          }
        }
        await tempConfigFile.writeAsString(jsonEncode(parsedJson));

        // Start Process
        final processFuture = Process.start(
          binPath,
          ['run', '-c', tempConfigFile.path],
          runInShell: false,
          workingDirectory: p.dirname(binPath),
          environment: {'ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS': 'true'},
        );

        process = await processFuture.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException("Process spawn timed out");
          },
        );

        AdvancedLogger.warn(
          '[TESTER] Native Process Spawned. PID: ${process!.pid}',
        );

        onProcess(process); // Register for watchdog
        registerProcess(process!);
        await Future.delayed(const Duration(milliseconds: 500));

        AdvancedLogger.warn(
          '[TESTER] Waiting for local socket to become ready...',
        );

        // Setup Client
        // FIX: SingboxConfigGenerator sets HTTP port to listenPort + 1
        // Use port + 1 for HTTP request
        dartHttpClient.findProxy = (uri) => "PROXY 127.0.0.1:${port + 1}";
        dartHttpClient.connectionTimeout = const Duration(seconds: 5);

        // STAGE 1 (TCP)
        // Just check if port is open
        int attempts = 0;
        while (attempts < 3) {
          try {
            final socket = await Socket.connect(
              '127.0.0.1',
              port,
              timeout: const Duration(milliseconds: 1500),
            );
            socket.destroy();
            stage1Success = true;
            break;
          } catch (e) {
            attempts++;
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        if (!stage1Success)
          throw Exception("Local Proxy failed to start on port $port");

        // STAGE 2 (HTTP) with Retry for HandshakeException
        // Delay briefly to allow sing-box to establish upstream TLS
        await Future.delayed(const Duration(milliseconds: 500));

        final sw = Stopwatch()..start();
        int httpAttempts = 0;

        while (httpAttempts < 2) {
          try {
            AdvancedLogger.warn(
              '[TESTER] HTTP Probe started to http://127.0.0.1:${port + 1} (Attempt ${httpAttempts + 1})',
            );
            final req = await dartHttpClient.getUrl(
              Uri.parse('https://www.google.com/generate_204'),
            );
            final resp = await req.close().timeout(const Duration(seconds: 5));
            sw.stop();

            AdvancedLogger.warn(
              '[TESTER] HTTP Response received: ${resp.statusCode}',
            );

            if (resp.statusCode == 204) {
              latency = sw.elapsedMilliseconds;
              stage2Success = true;
              break;
            } else {
              throw Exception("Status ${resp.statusCode}");
            }
          } catch (e) {
            httpAttempts++;
            if (httpAttempts < 2 &&
                (e.toString().contains('HandshakeException') ||
                    e.toString().contains('SocketException'))) {
              AdvancedLogger.warn(
                  '[TESTER] HTTP Handshake failed, retrying in 1s... $e');
              await Future.delayed(const Duration(seconds: 1));
            } else {
              AdvancedLogger.warn('[TESTER] HTTP Response Error: $e');
              throw Exception("Stage 2 Failed: $e");
            }
          }
        }

        // STAGE 3 (Speed)
        if (mode == TestMode.speed) {
          int bytes = 0;
          final speedSw = Stopwatch();
          try {
            speedSw.start();
            final speedReq = await dartHttpClient.getUrl(
              Uri.parse('https://speed.cloudflare.com/__down?bytes=1000000'),
            );
            final speedResp = await speedReq.close();
            await speedResp
                .listen((chunk) {
                  bytes += chunk.length;
                })
                .asFuture()
                .timeout(const Duration(seconds: 5));
            speedSw.stop();
            final durationSec = speedSw.elapsedMilliseconds / 1000.0;
            if (durationSec > 0 && bytes > 0) {
              speedMbps = (bytes * 8) / (durationSec * 1000000);
            }
          } catch (e) {
            AdvancedLogger.warn("Stage 3 (Speed) failed: $e");
          }
        }

        int score = 0;
        if (speedMbps > 0) score += (speedMbps * 5).clamp(0, 50).toInt();
        if (latency > 0) score += (1000 ~/ latency).clamp(0, 50).toInt();

        final finalStage = (speedMbps > 0) ? 3 : 2;
        final newStageResults = Map<String, TestResult>.from(
          config.stageResults,
        );
        newStageResults['TCP'] = TestResult(success: true);
        newStageResults['HTTP'] = TestResult(success: true, latency: latency);
        if (speedMbps > 0)
          newStageResults['Speed'] = TestResult(success: true, latency: 0);

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
                speed: speedMbps,
              )
              .deviceMetrics,
        );
      } catch (e) {
        AdvancedLogger.warn("EphemeralTester Error (${config.name}): $e");
        String failedStage = "Init";
        if (!stage1Success)
          failedStage = "Stage1_ProxyInit";
        else if (!stage2Success)
          failedStage = "Stage2_HTTP";
        else
          failedStage = "Stage3_Speed";

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
            AdvancedLogger.info(
              "[EphemeralTester] Hard killing native process PID: ${process.pid} in finally block",
            );
            try {
              process.kill(ProcessSignal.sigkill);
            } catch (_) {}
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

        if (port > 0) PortAllocator().release(port);
        _windowsSemaphore.release();
      }
    }
  }
}
