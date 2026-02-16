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

  Future<int> getPing(String config) async {
    if (Platform.isWindows) {
      // Delegate to Windows service or EphemeralTester (usually handled in HomeProvider)
      // But if called here, return failure or implement windows logic if needed.
      return failedPingValue;
    }

    try {
      final int latency = await _methodChannel.invokeMethod('testConfig', {'config': config});
      return latency <= 0 ? failedPingValue : latency;
    } catch (e) {
      print("Failed to get latency: $e");
      return failedPingValue;
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
      // This prevents the UI from freezing during the heavy JSON generation
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
    if (Platform.isWindows) {
      await _windowsVpnService.stopVpn();
      _statusController.add("DISCONNECTED");
      return;
    }

    try {
      await _methodChannel.invokeMethod('stopVpn');
      _statusController.add("DISCONNECTED");
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
