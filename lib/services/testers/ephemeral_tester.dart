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

class EphemeralTester {
  static final EphemeralTester _instance = EphemeralTester._internal();
  factory EphemeralTester() => _instance;
  EphemeralTester._internal();

  final NativeVpnService _nativeVpnService = NativeVpnService();

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
    if (config.trim().startsWith('{')) {
      try {
        final json = jsonDecode(config);
        if (json is Map<String, dynamic>) {
          // Direct fields
          if (json.containsKey('server')) {
             return {'host': json['server'], 'port': int.tryParse(json['server_port']?.toString() ?? '443') ?? 443};
          }
          if (json.containsKey('remote_addr')) {
              final parts = json['remote_addr'].toString().split(':');
              if (parts.length == 2) {
                 return {'host': parts[0], 'port': int.tryParse(parts[1]) ?? 443};
              }
          }
          // Check outbounds
          if (json['outbounds'] is List) {
            for (var outbound in json['outbounds']) {
               if (outbound['type'] == 'selector' || outbound['type'] == 'urltest') continue;
               if (outbound['type'] == 'direct' || outbound['type'] == 'block') continue;
               if (outbound.containsKey('server')) {
                   return {'host': outbound['server'], 'port': int.tryParse(outbound['server_port']?.toString() ?? '443') ?? 443};
               }
            }
          }
        }
      } catch (_) {}
    }

    // 2. Delegate to SingboxConfigGenerator for URI schemes (vmess, vless, ss, etc.)
    // It handles Base64 decoding for vmess:// internally.
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
          final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
          socket.destroy();
          sw.stop();

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
             deviceMetrics: config.updateMetrics(
                deviceId: "android_dart_socket",
                ping: ping,
                speed: 0
             ).deviceMetrics
          );
       } catch (e) {
          AdvancedLogger.warn("EphemeralTester (Android) Error: $e");
          return config.copyWith(
             failureReason: "Socket Test Failed: $e",
             lastFailedStage: "Stage1_TCP",
             failureCount: config.failureCount + 1,
             lastTestedAt: DateTime.now(),
          );
       }
    }

    // --- WINDOWS / DESKTOP PATH ---
    int port = await findFreePort();
    if (port == 0) {
      return config.copyWith(
        failureReason: "No free ports",
        lastFailedStage: "Init",
        failureCount: config.failureCount + 1, // Soft fail
      );
    }

    Process? process;
    File? tempConfigFile;
    final testId = DateTime.now().millisecondsSinceEpoch;

    // Results containers
    bool stage1Success = (mode == TestMode.speed); // Assume success if skipping
    bool stage2Success = (mode == TestMode.speed); // Assume success if skipping
    double speedMbps = 0.0;
    int latency = (mode == TestMode.speed) ? (config.stageResults['HTTP']?.latency ?? 0) : 0;

    // Define HttpClient outside try/catch for cleanup
    final dartHttpClient = HttpClient();

    try {
      // 1. Prepare Config (JSON)
      // Use BinaryManager to reliably get the executable path
      final binPath = await BinaryManager.ensureBinary();

      final tempDir = await getTemporaryDirectory();
      tempConfigFile = File(p.join(tempDir.path, 'test_${config.id}_$testId.json'));

      // Generate JSON with strict constraints in background isolate to prevent UI lag
      final jsonConfig = await compute(_generateConfigWrapper, {
        'rawConfig': config.rawConfig,
        'listenPort': port,
        'isTest': true,
      });

      // Inject "fatal" log level & Inbounds/Route constraints if not already handled by generator
      // The generator handles basic structure, but we enforce specific test overrides here
      final Map<String, dynamic> parsedJson = jsonDecode(jsonConfig);

      // Override Log Level
      parsedJson['log'] = {
        "level": "fatal",
        "output": "stderr",
        "timestamp": true
      };

      // Ensure Inbounds bind to localhost
      if (parsedJson['inbounds'] is List) {
        for (var inbound in parsedJson['inbounds']) {
           inbound['listen'] = "127.0.0.1";
        }
      }

      // Ensure Routing (Google/Cloudflare -> Proxy)
      if (parsedJson['route'] == null) parsedJson['route'] = {};
      if (parsedJson['route']['rules'] == null) parsedJson['route']['rules'] = [];

      (parsedJson['route']['rules'] as List).insert(0, {
          "domain_suffix": ["google.com", "gstatic.com", "cloudflare.com"],
          "outbound": "proxy"
      });

      await tempConfigFile.writeAsString(jsonEncode(parsedJson));

      // 2. Spawn Process (With Hard Timeout)
      // We wrap the startup in a timeout to prevent hanging if binary is bad
      await Future.delayed(Duration.zero); // Yield

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

      // Wait for core to be ready (naive delay for now, or stream listen if not fatal)
      // Since we use fatal, we won't see logs. Trusting it starts fast.
      await Future.delayed(const Duration(milliseconds: 500));

      // Configure Proxy for HttpClient (Used for both Stage 2 & 3)
      dartHttpClient.findProxy = (uri) => "PROXY 127.0.0.1:${port + 1}"; // HTTP Inbound is port+1
      dartHttpClient.connectionTimeout = const Duration(seconds: 5); // 5s Timeout

      // --- STAGE 1: TCP Handshake (Availability) ---
      // Check if local port is listening (Proxy is up)
      if (mode != TestMode.speed) {
        int attempts = 0;
        while (attempts < 3) {
          try {
            final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 1500));
            socket.destroy();
            stage1Success = true;
            break; // Success
          } on SocketException catch (e) {
            if (e.osError?.errorCode == 1225 || e.osError?.errorCode == 10048) {
              attempts++;
              if (attempts < 3) {
                await Future.delayed(const Duration(seconds: 2)); // Wait for OS to release ports
                continue;
              }
            }
            throw Exception("Stage 1 Failed: Proxy port not reachable (${e.osError?.errorCode})");
          } catch (e) {
            throw Exception("Stage 1 Failed: Proxy port not reachable");
          }
        }
      }

      // --- STAGE 2: HTTP Ghost Buster (Real Connectivity) ---
      // Request: https://connectivitycheck.gstatic.com/generate_204
      // Proxy: 127.0.0.1:port+1 (HTTP Inbound)

      if (mode != TestMode.speed) {
        final sw = Stopwatch()..start();
        try {
           final req = await dartHttpClient.getUrl(Uri.parse('https://connectivitycheck.gstatic.com/generate_204'));
           final resp = await req.close();

           sw.stop();

           // STRICT STATUS CODE CHECK: Only 204 is valid.
           // 200 (Captive Portal), 302, 403, 502 are FAILURES.
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

      // --- STAGE 3: Speed Test (Quality) ---
      // Only run if mode is `speed`. We assume Stage 2 passed (or we skipped it).
      if (mode == TestMode.speed) {
         int bytes = 0;
         final speedSw = Stopwatch(); // Defined outside try

         try {
            speedSw.start();
            final speedReq = await dartHttpClient.getUrl(Uri.parse('http://speed.cloudflare.com/__down?bytes=1000000'));
            final speedResp = await speedReq.close();

            // Timeout 3s for download (OPTIMIZED)
            await speedResp.listen((chunk) {
               bytes += chunk.length;
            }).asFuture().timeout(const Duration(seconds: 3));

            speedSw.stop();

            final durationSec = speedSw.elapsedMilliseconds / 1000.0;
            if (durationSec > 0) {
               speedMbps = (bytes * 8) / (durationSec * 1000000);
            }
         } catch (e) {
            // Timeout or error: Calculate what we got
            AdvancedLogger.warn("Stage 3 (Speed) failed/timed out: $e");
            speedSw.stop();
            final durationSec = speedSw.elapsedMilliseconds / 1000.0;
            if (durationSec > 0 && bytes > 0) {
               speedMbps = (bytes * 8) / (durationSec * 1000000);
            }
         }
      }

    } catch (e) {
      AdvancedLogger.warn("EphemeralTester Error (${config.name}): $e");

      // Determine failure stage
      String failedStage = "Init";
      if (!stage1Success) failedStage = "Stage1_TCP";
      else if (!stage2Success) failedStage = "Stage2_HTTP";
      else failedStage = "Stage3_Speed";

      return config.copyWith(
         failureReason: e.toString(),
         lastFailedStage: failedStage,
         failureCount: config.failureCount + 1,
         lastTestedAt: DateTime.now(),
      );

    } finally {
      dartHttpClient.close(); // Close client
      // STRICT CLEANUP: Kill process in finally block
      try {
        if (process != null) {
          process!.kill(ProcessSignal.sigkill);
        }
      } catch (e) {
        AdvancedLogger.warn("EphemeralTester: Error killing process: $e");
      }

      try {
        if (tempConfigFile != null && await tempConfigFile.exists()) {
           await tempConfigFile.delete();
        }
      } catch (_) {}
    }

    // Success!
    int score = 0;
    if (speedMbps > 0) score += (speedMbps * 5).clamp(0, 50).toInt();
    if (latency > 0) score += (1000 ~/ latency).clamp(0, 50).toInt();

    // Determine final stage
    // If mode is connectivity, we stopped at 2. If speed, we finished 3.
    final finalStage = (mode == TestMode.connectivity) ? 2 : 3;

    // Build Results Map (Preserving previous results)
    final newStageResults = Map<String, TestResult>.from(config.stageResults);

    if (mode == TestMode.connectivity) {
       newStageResults['TCP'] = TestResult(success: true);
       newStageResults['HTTP'] = TestResult(success: true, latency: latency);
    } else if (mode == TestMode.speed) {
       // We assume TCP/HTTP passed previously, so we don't overwrite them.
       // Only add Speed result.
       newStageResults['Speed'] = TestResult(success: true, latency: 0); // Speed result doesn't track latency
    }

    return config.copyWith(
       funnelStage: finalStage,
       speedScore: score,
       stageResults: newStageResults,
       failureCount: 0,
       isAlive: true,
       lastTestedAt: DateTime.now(),
       // Update metrics
       deviceMetrics: config.updateMetrics(
          deviceId: "ephemeral",
          ping: latency,
          speed: speedMbps
       ).deviceMetrics
    );
  }
}
