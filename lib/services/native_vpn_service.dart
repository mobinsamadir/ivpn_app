import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // For compute
import 'dart:async';
import 'ffi_utils.dart';
import 'singbox_config_generator.dart'; // ✅ Standardized Generator

// Top-level function for compute to prevent UI lag
String _generateConfigWrapper(Map<String, dynamic> args) {
  return SingboxConfigGenerator.generateConfig(
    args['rawLink'],
    listenPort: args['listenPort'],
  );
}

class NativeVpnService {
  static const _methodChannel = MethodChannel('com.example.ivpn_new/method');
  static const _eventChannel = EventChannel('com.example.ivpn_new/events');

  // Standard FFI initialization (Standardized Path)
  // Lazy load to prevent crash during unit testing
  dynamic get lib => FFILoader.lib;

  static const int failedPingValue = -1;

  StreamController<String> _statusController = StreamController<String>.broadcast();

  Future<int> getPing(String config) async {
    try {
      final int latency = await _methodChannel.invokeMethod('test_config', {'config': config});
      return latency == 0 ? 1 : latency;
    } catch (e) {
      print("Failed to get latency: $e");
      return failedPingValue;
    }
  }

  Future<void> connect(String rawLink) async {
    try {
      // Generate Sing-box JSON config from raw link using shared logic in a background isolate
      // This prevents the UI from freezing during the heavy JSON generation
      final String configJson = await compute(_generateConfigWrapper, {
        'rawLink': rawLink,
        'listenPort': 10808,
      });

      print("🚀 [Native] Connecting with config length: ${configJson.length}...");
      await _methodChannel.invokeMethod('connect', {'config': configJson});
      _statusController.add("CONNECTED");
      print("✅ [Native] Connect command sent.");
    } catch (e) {
      print("Failed to send connect command: $e");
      _statusController.add("ERROR");
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await _methodChannel.invokeMethod('disconnect');
      _statusController.add("DISCONNECTED");
      print("Disconnect command sent.");
    } catch (e) {
      print("Failed to send disconnect command: $e");
    }
  }

  Stream<String> get connectionStatusStream {
    return _statusController.stream;
  }

  void dispose() {
    _statusController.close();
  }
}
