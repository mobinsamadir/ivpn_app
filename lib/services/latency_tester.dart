import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/file_logger.dart';
import '../utils/advanced_logger.dart';
import 'singbox_config_generator.dart';
import 'windows_vpn_service.dart';

class LatencyTester {
  static const int START_PORT = 10850;
  static const int END_PORT = 10950;
  static int _nextPort = 20000;
  static final Random _rng = Random();

  // Returns milliseconds or -1 (Timeout/Error)
  static Future<int> measureLatency(String configRaw, {int timeoutMs = 35000}) async {
    // Force kill any existing sing-box processes to free up ports
    if (Platform.isWindows) {
      try {
        await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']);
        // Give Windows time to release the port
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        // Ignore errors if no process is found
      }
    }

    final completer = Completer<int>();
    Process? process;
    // Use a random port between 30000 and 40000 to reduce collision probability
    final int port = 30000 + _rng.nextInt(10000);
    final tempDir = await getTemporaryDirectory();
    final configFile = File(p.join(tempDir.path, 'latency_$port.json'));
    
    try {
      final service = WindowsVpnService();
      final exePath = await service.getExecutablePath();
      final binDir = p.dirname(exePath);
      
      // Generate config on custom port
      final jsonString = SingboxConfigGenerator.generateConfig(configRaw, listenPort: port, isTest: true);
      await configFile.writeAsString(jsonString);

      process = await Process.start(
        exePath,
        ['run', '-c', configFile.path, '-D', '.'],
        workingDirectory: binDir,
        environment: {
          'ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS': 'true',
        },
      );

      final startCompleter = Completer<void>();

      // Capture core logs for debugging
      process.stdout.transform(utf8.decoder).listen((data) {
        final line = data.trim();
        AdvancedLogger.info("[NEW-TESTER] [CORE-OUT] $line");
        if (!startCompleter.isCompleted && (line.contains("started") || line.contains("inbound/http"))) {
          startCompleter.complete();
        }
      });
      process.stderr.transform(utf8.decoder).listen((data) {
        AdvancedLogger.warning("[NEW-TESTER] [CORE-ERR] ${data.trim()}");
      });
      
      // Early exit detection: if core crashes, complete with -1 immediately
      process.exitCode.then((code) {
        if (code != 0 && !completer.isCompleted) {
          FileLogger.log("Sing-box core crashed with code $code for port $port");
          if (!startCompleter.isCompleted) {
            startCompleter.completeError("Crashed");
          }
          completer.complete(-1);
        }
      });

      final stopwatch = Stopwatch()..start();
      
      // Use a timer for the overall timeout
      final timeoutTimer = Timer(Duration(milliseconds: timeoutMs), () {
        if (!completer.isCompleted) {
          completer.complete(-1);
        }
      });

      try {
        // Wait for core to be ready
        try {
          await startCompleter.future.timeout(const Duration(seconds: 5));
          AdvancedLogger.info("✅ [READY] Core is running. Sending Ping...");
        } catch (e) {
          AdvancedLogger.error("❌ [ABORT] Core failed to start: $e");
          timeoutTimer.cancel();
          return -1;
        }

        final client = HttpClient();
        client.findProxy = (uri) => "PROXY 127.0.0.1:${port + 1}";
        client.connectionTimeout = const Duration(seconds: 10);
        
        const String targetUrl = "http://1.1.1.1";
        bool success = false;
        while (!success && stopwatch.elapsedMilliseconds < timeoutMs && !completer.isCompleted) {
          try {
            AdvancedLogger.info("[NEW-TESTER] Dart: 🚀 Sending request to $targetUrl via 127.0.0.1:${port + 1}");
            AdvancedLogger.info("[NEW-TESTER] Dart: ⏳ Waiting for response...");
            
            final request = await client.headUrl(Uri.parse(targetUrl))
                .timeout(const Duration(seconds: 10));
            final response = await request.close();
            
            AdvancedLogger.info("[NEW-TESTER] Dart: 📩 Received response: ${response.statusCode}");
            
            if (response.statusCode == 204 || response.statusCode == 200) {
              AdvancedLogger.info("[NEW-TESTER] Dart: ✅ Connected/Got response");
              success = true;
            } else {
              await Future.delayed(const Duration(milliseconds: 500));
            }
          } catch (e) {
            AdvancedLogger.error("[NEW-TESTER] Dart: 💥 Request failed: $e");
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        
        stopwatch.stop();
        timeoutTimer.cancel();
        
        if (success && !completer.isCompleted) {
          completer.complete(stopwatch.elapsedMilliseconds);
        }
      } catch (e) {
        // Error in client logic
      }

      return await completer.future;
      
    } catch (e) {
      FileLogger.log("Ping Error: $e");
      return -1;
    } finally {
      process?.kill();
      // Double tap to be sure on Windows
      if (Platform.isWindows && process != null) {
         Process.run('taskkill', ['/F', '/PID', '${process.pid}']);
      }
      
      // Cleanup unique config file
      if (await configFile.exists()) {
        try {
          await configFile.delete();
        } catch (e) {
          // Ignore deletion errors
        }
      }
    }
  }

  static Future<void> _killSingboxProcess() async {
    if (Platform.isWindows) {
      try {
        // Forcefully kill any existing sing-box processes to free up ports
        await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']);
      } catch (e) {
        // Ignore errors if no process is found
      }
    }
  }
}
