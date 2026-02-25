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

  final StreamController<String> _statusController = StreamController<String>.broadcast();

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
          bool isStatus = ["CONNECTED", "CONNECTING", "DISCONNECTED", "RECONNECTING", "PAUSED"].contains(message)
                          || message.startsWith("ERROR");

          if (isStatus) {
             _statusController.add(message);
          }
        },
        onError: (error) {
          AdvancedLogger.error("❌ [Native Event] Error: $error");
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
      final int latency = await _methodChannel.invokeMethod('testConfig', {'config': config});
      return latency <= 0 ? failedPingValue : latency;
    } catch (e) {
      AdvancedLogger.error("Failed to get latency: $e");
      return failedPingValue;
    }
  }

  // --- NEW: Granular Test Control ---

  /// Starts a lightweight Sing-box proxy for testing.
  /// Returns the SOCKS port on success, or negative error code.
  Future<int> startTestProxy(String configJson) async {
    if (Platform.isWindows) return -1; // Handled by EphemeralTester directly on Windows

    // 1. Diagnostic Log (First 10 chars)
    final String start = configJson.length > 10 ? configJson.substring(0, 10) : configJson;
    AdvancedLogger.warn("[DEBUG-INTERNAL] Config start: $start");

    // 2. Validate Format
    if (!configJson.trim().startsWith('{')) {
       AdvancedLogger.error("FATAL: INVALID CONFIG FORMAT DETECTED. Expected JSON, got: $start...");
       return -1;
    }

    try {
       if (kDebugMode) {
          AdvancedLogger.info("DEBUG_CONFIG: $configJson");
       }
       final int result = await _methodChannel.invokeMethod('startTestProxy', {'config': configJson});
       return result;
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
        'listenPort': 10808, // Hardcoded for main VPN connection to avoid conflict with random test ports
      });

      // CONFIG DUMP: Critical Diagnostic
      AdvancedLogger.warn("[CORE-INPUT-JSON] $configJson");

      // 1. Diagnostic Log (First 10 chars)
      final String start = configJson.length > 10 ? configJson.substring(0, 10) : configJson;
      AdvancedLogger.warn("[DEBUG-INTERNAL] Config start: $start");

      // 2. Validate Format
      if (!configJson.trim().startsWith('{')) {
         AdvancedLogger.error("FATAL: INVALID CONFIG FORMAT DETECTED. Expected JSON, got: $start...");
         throw Exception("Invalid Config Format (Not JSON)");
      }

      AdvancedLogger.info("🚀 [Native] Connecting with config length: ${configJson.length}...");
      // if (kDebugMode) {
      //    AdvancedLogger.info("DEBUG_CONFIG: $configJson");
      // }
      await _methodChannel.invokeMethod('startVpn', {'config': configJson});

      // CRITICAL FIX: Removed fake "CONNECTED" state.
      // Now we wait for the OS to emit the real state via EventChannel.
      AdvancedLogger.info("✅ [Native] Connect command sent. Waiting for OS confirmation...");
    } catch (e) {
      AdvancedLogger.error("Failed to send connect command: $e");
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

  void dispose() {
    _statusController.close();
  }
}
