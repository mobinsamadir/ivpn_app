import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // For compute
import 'dart:async';
import 'dart:io';
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
  // Updated channel name to match Kotlin side
  static const _methodChannel = MethodChannel('com.example.ivpn/vpn');

  final WindowsVpnService _windowsVpnService = WindowsVpnService();

  static const int failedPingValue = -1;

  final StreamController<String> _statusController = StreamController<String>.broadcast();

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
      print("Failed to get latency: $e");
      return failedPingValue;
    }
  }

  // --- NEW: Granular Test Control ---

  /// Starts a lightweight Sing-box proxy for testing.
  /// Returns the SOCKS port on success, or negative error code.
  Future<int> startTestProxy(String configJson) async {
    if (Platform.isWindows) return -1; // Handled by EphemeralTester directly on Windows

    try {
       final int result = await _methodChannel.invokeMethod('startTestProxy', {'config': configJson});
       return result;
    } catch (e) {
       print("Failed to start test proxy: $e");
       return -1;
    }
  }

  /// Stops the testing proxy.
  Future<void> stopTestProxy() async {
    if (Platform.isWindows) return;

    try {
      await _methodChannel.invokeMethod('stopTestProxy');
    } catch (e) {
      print("Failed to stop test proxy: $e");
    }
  }

  Future<void> connect(String rawLink) async {
    if (Platform.isWindows) {
      await _windowsVpnService.startVpn(rawLink);
      _statusController.add("CONNECTED");
      return;
    }

    try {
      // Generate Sing-box JSON config from raw link using shared logic in a background isolate
      final String configJson = await compute(_generateConfigWrapper, {
        'rawLink': rawLink,
        'listenPort': 10808,
      });

      print("🚀 [Native] Connecting with config length: ${configJson.length}...");
      await _methodChannel.invokeMethod('startVpn', {'config': configJson});
      _statusController.add("CONNECTED");
      print("✅ [Native] Connect command sent.");
    } catch (e) {
      print("Failed to send connect command: $e");
      _statusController.add("ERROR");
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _statusController.add("DISCONNECTED");

    if (Platform.isWindows) {
      await _windowsVpnService.stopVpn();
      return;
    }

    try {
      await _methodChannel.invokeMethod('stopVpn');
      print("Disconnect command sent.");
    } catch (e) {
      print("Failed to send disconnect command: $e");
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
