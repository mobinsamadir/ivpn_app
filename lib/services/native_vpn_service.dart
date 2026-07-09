import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // For compute
import 'dart:async';
import 'dart:io';
import '../utils/advanced_logger.dart';
import 'singbox_config_generator.dart';
import 'windows_vpn_service.dart';

// Top-level function for compute to prevent UI lag
String _generateConfigWrapper(Map<String, dynamic> args) {
  return SingboxConfigGenerator.generateConfig(
    args['rawLink'],
    listenPort: args['listenPort'],
  );
}

class NativeVpnService {
  // Singleton
  static final NativeVpnService _instance = NativeVpnService._internal();
  factory NativeVpnService() => _instance;

  NativeVpnService._internal() {
    _init();
  }

  // Updated channel name to match Kotlin side
  static const _methodChannel = MethodChannel('com.example.ivpn/vpn');
  // CRITICAL FIX: Real-time status updates from Native OS
  static const _eventChannel = EventChannel('com.example.ivpn/vpn_status');

  final WindowsVpnService _windowsVpnService = WindowsVpnService();

  static const int failedPingValue = -1;

  // Stats stream
  static const _statsEventChannel = EventChannel('vpn_stats');

  Stream<Map<String, int>> get statsStream {
    if (!Platform.isAndroid) return const Stream.empty();
    return _statsEventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return {
          'rx': (event['rx'] as num).toInt(),
          'tx': (event['tx'] as num).toInt(),
        };
      }
      return {'rx': 0, 'tx': 0};
    });
  }

  String? _lastKnownState;

  late final StreamController<String> _statusController =
      StreamController<String>.broadcast(
    onListen: () {
      if (_lastKnownState != null && !_statusController.isClosed) {
        _statusController.add(_lastKnownState!);
      }
    },
  );

  // Initialization logic moved here
  void _init() {
    // Initialize Event Channel Listener for Android
    if (!Platform.isWindows) {
      _eventChannel.receiveBroadcastStream().listen(
        (event) {
          final String message = event.toString();

          // 1. Always log to Console/File (Requirement: Native Log Redirection)
          // CRITICAL: Use WARN to ensure it shows in Release mode per request
          AdvancedLogger.warn("[V2RAY_CORE] $message");

          // 2. Smart Filter: Only update UI for valid status changes to prevent UI jank
          // Known statuses: CONNECTED, CONNECTING, DISCONNECTED, RECONNECTING
          // Errors start with ERROR
          bool isStatus = [
                "CONNECTED",
                "CONNECTING",
                "DISCONNECTED",
                "RECONNECTING",
                "PAUSED",
              ].contains(message) ||
              message.startsWith("ERROR");

          if (isStatus) {
            _lastKnownState = message;
            _statusController.add(message);
          }
        },
        onError: (error) {
          AdvancedLogger.error("❌ [Native Event] Error: $error");
          _lastKnownState = "ERROR: NATIVE_EVENT: $error";
          _statusController.add("ERROR: NATIVE_EVENT: $error");
        },
      );
    }
  }

  Future<bool> isAdmin() async {
    if (Platform.isWindows) {
      return await _windowsVpnService.isAdmin();
    }
    return true;
  }

  // Legacy Ping (One-shot)
  Future<int> getPing(String config) async {
    if (Platform.isWindows) return failedPingValue;

    try {
      final int latency = await _methodChannel.invokeMethod('testConfig', {
        'config': config,
      });
      return latency <= 0 ? failedPingValue : latency;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        AdvancedLogger.warn("VPN Permission not granted. Skipping test.");
        return failedPingValue;
      }
      AdvancedLogger.error("Failed to get latency: $e");
      return failedPingValue;
    } catch (e) {
      AdvancedLogger.error("Failed to get latency: $e");
      return failedPingValue;
    }
  }

  // --- NEW: Granular Test Control ---

  /// Starts a lightweight Sing-box proxy for testing.
  /// Returns the SOCKS port on success, or negative error code.
  Future<int> startTestProxy(String configJson) async {
    if (Platform.isWindows)
      return -1; // Handled by EphemeralTester directly on Windows

    // CRITICAL: Prevent passing null/empty or malformed strings to native layer
    if (configJson.trim().isEmpty) {
      AdvancedLogger.error("startTestProxy called with empty configuration");
      return -1;
    }

    // 1. Diagnostic Log (First 10 chars)
    final String start =
        configJson.length > 10 ? configJson.substring(0, 10) : configJson;
    AdvancedLogger.warn("[DEBUG-INTERNAL] Config start: $start");

    // 2. Validate Format
    if (!configJson.trim().startsWith('{')) {
      AdvancedLogger.error(
        "FATAL: INVALID CONFIG FORMAT DETECTED. Expected JSON, got: $start...",
      );
      return -1;
    }

    try {
      if (kDebugMode) {
        AdvancedLogger.info("DEBUG_CONFIG: $configJson");
      }
      final int result = await _methodChannel.invokeMethod('startTestProxy', {
        'config': configJson,
      });
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        AdvancedLogger.warn(
            "VPN Permission not granted. Skipping proxy start.");
        return -1;
      }
      AdvancedLogger.error("Failed to start test proxy: $e");
      return -1;
    } catch (e) {
      AdvancedLogger.error("Failed to start test proxy: $e");
      return -1;
    }
  }

  /// Stops the testing proxy.
  Future<void> stopTestProxy() async {
    if (Platform.isWindows) return;

    try {
      await _methodChannel.invokeMethod('stopTestProxy');
    } catch (e) {
      AdvancedLogger.error("Failed to stop test proxy: $e");
    }
  }

  Future<void> connect(String rawLink) async {
    if (Platform.isWindows) {
      await _windowsVpnService.startVpn(rawLink);
      // Windows service handles its own stream updates
      return;
    }

    try {
      // Generate Sing-box JSON config from raw link using shared logic in a background isolate
      final String configJson = await compute(_generateConfigWrapper, {
        'rawLink': rawLink,
        'listenPort':
            10808, // Hardcoded for main VPN connection to avoid conflict with random test ports
      });

      // CONFIG DUMP: Critical Diagnostic
      AdvancedLogger.warn("[CORE-INPUT-JSON] $configJson");

      // 1. Diagnostic Log (First 10 chars)
      final String start =
          configJson.length > 10 ? configJson.substring(0, 10) : configJson;
      AdvancedLogger.warn("[DEBUG-INTERNAL] Config start: $start");

      // 2. Validate Format
      if (!configJson.trim().startsWith('{')) {
        AdvancedLogger.error(
          "FATAL: INVALID CONFIG FORMAT DETECTED. Expected JSON, got: $start...",
        );
        throw Exception("Invalid Config Format (Not JSON)");
      }

      AdvancedLogger.info(
        "🚀 [Native] Connecting with config length: ${configJson.length}...",
      );
      // if (kDebugMode) {
      //    AdvancedLogger.info("DEBUG_CONFIG: $configJson");
      // }
      await _methodChannel.invokeMethod('startVpn', {'config': configJson});

      AdvancedLogger.info(
        "✅ [Native] Connect command sent. Waiting for OS confirmation...",
      );

      // Start cancelable timeout logic to listen for state update
      Timer? timeoutTimer;
      StreamSubscription<String>? statusSub;

      timeoutTimer = Timer(const Duration(seconds: 15), () async {
        AdvancedLogger.warn(
            "Native layer timed out. Forcing stopVpn and injecting ERROR event.");
        await statusSub?.cancel();

        try {
          await _methodChannel.invokeMethod('stopVpn');
        } catch (e) {
          AdvancedLogger.error(
              "Failed to cleanup Native VPN after timeout: $e");
        }

        if (!_statusController.isClosed) {
          _lastKnownState = "ERROR: NATIVE_TIMEOUT";
          _statusController.add("ERROR: NATIVE_TIMEOUT");
        }
      });

      statusSub = connectionStatusStream.listen((status) {
        if (status == "CONNECTED" ||
            status.startsWith("ERROR") ||
            status == "DISCONNECTED") {
          timeoutTimer?.cancel();
          statusSub?.cancel();
        }
      });
    } catch (e) {
      AdvancedLogger.error("Failed to send connect command: $e");
      _lastKnownState = "ERROR: START_FAILED: $e";
      _statusController.add("ERROR: START_FAILED: $e");
      rethrow;
    }
  }

  Future<void> disconnect() async {
    // CRITICAL FIX: Removed fake "DISCONNECTED" state.
    // The OS will emit DISCONNECTED when the interface goes down.

    if (Platform.isWindows) {
      await _windowsVpnService.stopVpn();
      return;
    }

    try {
      await _methodChannel.invokeMethod('stopVpn');
      AdvancedLogger.info("Disconnect command sent.");
    } catch (e) {
      AdvancedLogger.error("Failed to send disconnect command: $e");
    }
  }

  Stream<String> get connectionStatusStream {
    if (Platform.isWindows) {
      return _windowsVpnService.statusStream;
    }
    return _statusController.stream;
  }

  @visibleForTesting
  void resetForTesting() {
    _lastKnownState = null;
  }

  void dispose() {
    _statusController.close();
  }
}
