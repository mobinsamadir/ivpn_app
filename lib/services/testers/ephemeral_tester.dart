import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/vpn_config_with_metrics.dart';
import '../singbox_config_generator.dart';
import '../../utils/advanced_logger.dart';
import '../binary_manager.dart';

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

  // Track active processes to kill on exit
  static final List<Process> _activeProcesses = [];

  static void killAll() {
    AdvancedLogger.info("EphemeralTester: Killing all ${_activeProcesses.length} active processes...");
    for (final p in List.from(_activeProcesses)) {
      try {
        p.kill(ProcessSignal.sigkill);
      } catch (e) {
        AdvancedLogger.warn("EphemeralTester: Error killing process in killAll: $e");
      }
    }
    _activeProcesses.clear();
  }

  /// Finds a free port on the localhost loopback interface.
  Future<int> findFreePort() async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      return port;
    } catch (e) {
      AdvancedLogger.error("EphemeralTester: Failed to bind free port: $e");
      return 0;
    } finally {
      await socket?.close();
    }
  }

  /// Helper to extract host/port from config string
  Map<String, dynamic>? _extractHostPort(String config) {
    // 1. Try parsing as JSON first (if it looks like JSON)
    final trimmed = config.trim();
    if (trimmed.startsWith('{')) {
      try {
        final json = jsonDecode(trimmed);
        if (json is Map<String, dynamic>) {
          // Direct fields (server, remote_addr, address)
          if (json.containsKey('server')) {
             return {'host': json['server'], 'port': int.tryParse(json['server_port']?.toString() ?? '443') ?? 443};
          }
          if (json.containsKey('remote_addr')) {
              final parts = json['remote_addr'].toString().split(':');
              if (parts.length == 2) {
                 return {'host': parts[0], 'port': int.tryParse(parts[1]) ?? 443};
              }
          }
          if (json.containsKey('address')) {
              return {'host': json['address'], 'port': int.tryParse(json['port']?.toString() ?? '443') ?? 443};
          }

          // Check outbounds
          if (json['outbounds'] is List) {
            for (var outbound in json['outbounds']) {
               if (outbound['type'] == 'selector' || outbound['type'] == 'urltest') continue;
               if (outbound['type'] == 'direct' || outbound['type'] == 'block') continue;

               if (outbound.containsKey('server')) {
                   return {'host': outbound['server'], 'port': int.tryParse(outbound['server_port']?.toString() ?? '443') ?? 443};
               }
               if (outbound.containsKey('address')) {
                   return {'host': outbound['address'], 'port': int.tryParse(outbound['port']?.toString() ?? '443') ?? 443};
               }
            }
          }
        }
      } catch (_) {
        // Fallback or ignore JSON parsing error
      }
    }

    // 2. Delegate to SingboxConfigGenerator for URI schemes (vmess, vless, ss, etc.)
    return SingboxConfigGenerator.extractServerDetails(config);
  }

  /// Runs the Funnel Test on a specific config based on the mode.
  /// Returns a VpnConfigWithMetrics object with updated stageResults and scores.
  Future<VpnConfigWithMetrics> runTest(VpnConfigWithMetrics config, {TestMode mode = TestMode.speed}) async {
    // --- ANDROID DART SOCKET PATH ---
    if (Platform.isAndroid) {
       try {
          final details = _extractHostPort(config.rawConfig);
          if (details == null) throw Exception("Could not extract server details");

          final String host = details['host'];
          final int port = details['port'];

          // Socket Connect (TCP Handshake)
          final sw = Stopwatch()..start();
          Socket? socket;
          try {
             socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
             sw.stop();
          } finally {
             // CLEANUP: Ensure socket is destroyed even on timeout/error
             socket?.destroy();
          }

          final ping = sw.elapsedMilliseconds;

          // Success
          final newStageResults = Map<String, TestResult>.from(config.stageResults);
          newStageResults['TCP'] = TestResult(success: true);
          newStageResults['HTTP'] = TestResult(success: true, latency: ping); // Mocking HTTP stage with TCP latency

          // Calculate partial score
          int score = (1000 ~/ ping).clamp(0, 50).toInt();

          return config.copyWith(
             funnelStage: 2,
             speedScore: score,
             stageResults: newStageResults,
             failureCount: 0,
             isAlive: true,
             lastTestedAt: DateTime.now(),
             lastSuccessfulConnectionTime: DateTime.now().millisecondsSinceEpoch, // Mark implicit success for sorting
             deviceMetrics: config.updateMetrics(
                deviceId: "android_dart_socket",
                ping: ping,
                speed: 0,
                connectionSuccess: true
             ).deviceMetrics
          );
       } catch (e) {
          AdvancedLogger.warn("EphemeralTester (Android) Error: $e");
          return config.copyWith(
             funnelStage: 0, // Reset stage on failure
             failureReason: "Socket Test Failed: $e",
             lastFailedStage: "Stage1_TCP",
             failureCount: config.failureCount + 1,
             lastTestedAt: DateTime.now(),
             // FORCE -1 PING on failure
             ping: -1,
             deviceMetrics: config.updateMetrics(
                deviceId: "android_dart_socket",
                ping: -1,
                speed: 0,
                connectionSuccess: false
             ).deviceMetrics
          );
       }
    }

    // --- WINDOWS / DESKTOP PATH ---
    // Acquire Semaphore
    await _windowsSemaphore.acquire();

    int port = 0;
    Process? process;
    File? tempConfigFile;
    final dartHttpClient = HttpClient();

    try {
        port = await findFreePort();
        if (port == 0) {
          return config.copyWith(
            funnelStage: 0,
            failureReason: "No free ports",
            lastFailedStage: "Init",
            failureCount: config.failureCount + 1,
            ping: -1,
          );
        }

        final testId = DateTime.now().millisecondsSinceEpoch;

        // Results containers
        bool stage1Success = (mode == TestMode.speed);
        bool stage2Success = (mode == TestMode.speed);
        double speedMbps = 0.0;
        int latency = (mode == TestMode.speed) ? (config.stageResults['HTTP']?.latency ?? 0) : 0;

        // 1. Prepare Config (JSON)
        final binPath = await BinaryManager.ensureBinary();
        final tempDir = await getTemporaryDirectory();
        tempConfigFile = File(p.join(tempDir.path, 'test_${config.id}_$testId.json'));

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

        if (parsedJson['route'] == null) parsedJson['route'] = {};
        if (parsedJson['route']['rules'] == null) parsedJson['route']['rules'] = [];

        (parsedJson['route']['rules'] as List).insert(0, {
            "domain_suffix": ["google.com", "gstatic.com", "cloudflare.com"],
            "outbound": "proxy"
        });

        await tempConfigFile.writeAsString(jsonEncode(parsedJson));

        // 2. Spawn Process
        await Future.delayed(Duration.zero);

        AdvancedLogger.info("EphemeralTester: Spawning core on port $port for ${config.name}");

        final processFuture = Process.start(
          binPath,
          ['run', '-c', tempConfigFile.path],
          runInShell: false,
          workingDirectory: p.dirname(binPath),
          environment: {'ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS': 'true'},
        );

        process = await processFuture.timeout(const Duration(seconds: 5), onTimeout: () {
           throw TimeoutException("Process spawn timed out");
        });

        _activeProcesses.add(process);

        await Future.delayed(const Duration(milliseconds: 500));

        dartHttpClient.findProxy = (uri) => "PROXY 127.0.0.1:${port + 1}";
        dartHttpClient.connectionTimeout = const Duration(seconds: 5);

        // --- STAGE 1 ---
        if (mode != TestMode.speed) {
          int attempts = 0;
          while (attempts < 3) {
            try {
              final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 1500));
              socket.destroy();
              stage1Success = true;
              break;
            } on SocketException catch (e) {
              if (e.osError?.errorCode == 1225 || e.osError?.errorCode == 10048) {
                attempts++;
                if (attempts < 3) {
                  await Future.delayed(const Duration(seconds: 2));
                  continue;
                }
              }
              throw Exception("Stage 1 Failed: Proxy port not reachable (${e.osError?.errorCode})");
            } catch (e) {
              throw Exception("Stage 1 Failed: Proxy port not reachable");
            }
          }
        }

        // --- STAGE 2 ---
        if (mode != TestMode.speed) {
          final sw = Stopwatch()..start();
          try {
             final req = await dartHttpClient.getUrl(Uri.parse('https://connectivitycheck.gstatic.com/generate_204'));
             final resp = await req.close();

             sw.stop();

             if (resp.statusCode == 204) {
                latency = sw.elapsedMilliseconds;
                stage2Success = true;
             } else {
                throw Exception("Stage 2 Failed: Status ${resp.statusCode} (Expected 204)");
             }
          } catch (e) {
             throw Exception("Stage 2 Failed: $e");
          }
        }

        // --- STAGE 3 ---
        if (mode == TestMode.speed) {
           int bytes = 0;
           final speedSw = Stopwatch();

           try {
              speedSw.start();
              final speedReq = await dartHttpClient.getUrl(Uri.parse('http://speed.cloudflare.com/__down?bytes=1000000'));
              final speedResp = await speedReq.close();

              await speedResp.listen((chunk) {
                 bytes += chunk.length;
              }).asFuture().timeout(const Duration(seconds: 3));

              speedSw.stop();

              final durationSec = speedSw.elapsedMilliseconds / 1000.0;
              if (durationSec > 0) {
                 speedMbps = (bytes * 8) / (durationSec * 1000000);
              }
           } catch (e) {
              AdvancedLogger.warn("Stage 3 (Speed) failed/timed out: $e");
              speedSw.stop();
              final durationSec = speedSw.elapsedMilliseconds / 1000.0;
              if (durationSec > 0 && bytes > 0) {
                 speedMbps = (bytes * 8) / (durationSec * 1000000);
              }
           }
        }

        // Success Logic
        int score = 0;
        if (speedMbps > 0) score += (speedMbps * 5).clamp(0, 50).toInt();
        if (latency > 0) score += (1000 ~/ latency).clamp(0, 50).toInt();

        final finalStage = (mode == TestMode.connectivity) ? 2 : 3;
        final newStageResults = Map<String, TestResult>.from(config.stageResults);

        if (mode == TestMode.connectivity) {
           newStageResults['TCP'] = TestResult(success: true);
           newStageResults['HTTP'] = TestResult(success: true, latency: latency);
        } else if (mode == TestMode.speed) {
           newStageResults['Speed'] = TestResult(success: true, latency: 0);
        }

        return config.copyWith(
           funnelStage: finalStage,
           speedScore: score,
           stageResults: newStageResults,
           failureCount: 0,
           isAlive: true,
           lastTestedAt: DateTime.now(),
           lastSuccessfulConnectionTime: DateTime.now().millisecondsSinceEpoch, // Updated success time
           deviceMetrics: config.updateMetrics(
              deviceId: "ephemeral",
              ping: latency,
              speed: speedMbps
           ).deviceMetrics
        );

    } catch (e) {
      AdvancedLogger.warn("EphemeralTester Error (${config.name}): $e");

      String failedStage = "Init";
      if (!stage1Success) failedStage = "Stage1_TCP";
      else if (!stage2Success) failedStage = "Stage2_HTTP";
      else failedStage = "Stage3_Speed";

      return config.copyWith(
         funnelStage: 0, // Reset stage on failure
         failureReason: e.toString(),
         lastFailedStage: failedStage,
         failureCount: config.failureCount + 1,
         lastTestedAt: DateTime.now(),
         ping: -1, // Force invalid ping
      );
    } finally {
      dartHttpClient.close();
      try {
        if (process != null) {
          process!.kill(ProcessSignal.sigkill);
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

      // Release Semaphore
      _windowsSemaphore.release();
    }
  }
}
