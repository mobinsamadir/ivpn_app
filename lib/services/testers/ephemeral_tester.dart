import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/vpn_config_with_metrics.dart';
import '../singbox_config_generator.dart';
import '../../utils/advanced_logger.dart';
import '../windows_vpn_service.dart';

/// Test Modes
/// - `connectivity`: Stages 1 (TCP) & 2 (HTTP) only. Used for validation.
/// - `speed`: Stages 1, 2, & 3 (Download). Used for ranking.
enum TestMode { connectivity, speed }

class EphemeralTester {
  static final EphemeralTester _instance = EphemeralTester._internal();
  factory EphemeralTester() => _instance;
  EphemeralTester._internal();

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

  /// Runs the Funnel Test on a specific config based on the mode.
  /// Returns a VpnConfigWithMetrics object with updated stageResults and scores.
  Future<VpnConfigWithMetrics> runTest(VpnConfigWithMetrics config, {TestMode mode = TestMode.speed}) async {
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
    bool stage1Success = false; // TCP
    bool stage2Success = false; // Ghost/HTTP
    double speedMbps = 0.0;     // Speed
    int latency = 0;

    // Define HttpClient outside try/catch for cleanup
    final dartHttpClient = HttpClient();

    try {
      // 1. Prepare Config (JSON)
      final binPath = await _getSingboxPath();
      final tempDir = await getTemporaryDirectory();
      tempConfigFile = File(p.join(tempDir.path, 'test_${config.id}_$testId.json'));

      // Generate JSON with strict constraints
      final jsonConfig = SingboxConfigGenerator.generateConfig(
        config.rawConfig,
        listenPort: port,
        isTest: true,
      );

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

      // --- STAGE 1: TCP Handshake (Availability) ---
      // Check if local port is listening (Proxy is up)
      try {
        final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 1500));
        socket.destroy();
        stage1Success = true;
      } catch (e) {
        throw Exception("Stage 1 Failed: Proxy port not reachable");
      }

      // --- STAGE 2: HTTP Ghost Buster (Real Connectivity) ---
      // Request: https://connectivitycheck.gstatic.com/generate_204
      // Proxy: 127.0.0.1:port+1 (HTTP Inbound)

      dartHttpClient.findProxy = (uri) => "PROXY 127.0.0.1:${port + 1}"; // HTTP Inbound is port+1
      dartHttpClient.connectionTimeout = const Duration(seconds: 5); // 5s Timeout

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

      // --- STAGE 3: Speed Test (Quality) ---
      // Only run if mode is `speed` and Stage 2 passed
      if (mode == TestMode.speed && stage2Success) {
         int bytes = 0;
         final speedSw = Stopwatch(); // Defined outside try

         try {
            speedSw.start();
            final speedReq = await dartHttpClient.getUrl(Uri.parse('http://speed.cloudflare.com/__down?bytes=1000000'));
            final speedResp = await speedReq.close();

            // Timeout 5s for download
            await speedResp.listen((chunk) {
               bytes += chunk.length;
            }).asFuture().timeout(const Duration(seconds: 5));

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
      // STRICT CLEANUP
      try {
        process?.kill(ProcessSignal.sigkill);
      } catch (_) {}

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

    return config.copyWith(
       funnelStage: finalStage,
       speedScore: score,
       stageResults: {
          'TCP': TestResult(success: true),
          'HTTP': TestResult(success: true, latency: latency),
          if (mode == TestMode.speed) 'Speed': TestResult(success: true, latency: 0),
       },
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

  Future<String> _getSingboxPath() async {
     if (Platform.isWindows) {
        return await WindowsVpnService().getExecutablePath();
     } else if (Platform.isAndroid) {
        // Attempt to locate libsingbox.so or similar in application directory
        try {
           final appDir = await getApplicationSupportDirectory();
           final potentialPath = p.join(appDir.path, 'libsingbox.so');
           if (await File(potentialPath).exists()) return potentialPath;

           return "sing-box"; // Expecting it in PATH or fails
        } catch (e) {
           return "sing-box";
        }
     }
     return "sing-box"; // Fallback for Linux/MacOS
  }
}
