import 'dart:async';
import 'dart:io';
import 'advanced_logger.dart';

class PortAllocator {
  static final PortAllocator _instance = PortAllocator._internal();
  factory PortAllocator() => _instance;
  PortAllocator._internal();

  // Start at 11000 as requested
  static const int _startPort = 11000;
  static const int _maxPort = 65535;
  int _currentPort = _startPort;

  final Set<int> _activePorts = {};

  Future<int> allocate() async {
    // Basic loop to find next available port
    // We increment _currentPort globally to avoid re-using ports too quickly.
    // CRITICAL: We increment by 2 because Singbox uses [port] (SOCKS) and [port+1] (HTTP).
    // This prevents overlap between concurrent tests.

    int attempts = 0;
    while (attempts < 1000) {
      int port = 11000;

      // Synchronize access
      if (_currentPort > _maxPort - 1) {
        _currentPort = _startPort;
      }
      port = _currentPort;
      _currentPort += 2; // Reserve 2 ports

      // Check if either port is known to be active
      if (_activePorts.contains(port) || _activePorts.contains(port + 1)) {
        attempts++;
        continue;
      }

      // Check if both ports are free at OS level
      if (await _isPortFree(port) && await _isPortFree(port + 1)) {
        _activePorts.add(port);
        // We track the base port. We assume port+1 is also effectively reserved/used by the same owner.
        AdvancedLogger.info("PortAllocator: Allocated port block $port-${port+1}");
        return port;
      }

      attempts++;
    }

    throw Exception("PortAllocator: Failed to find a free port block after 1000 attempts");
  }

  void release(int port) {
    if (_activePorts.contains(port)) {
      _activePorts.remove(port);
      AdvancedLogger.info("PortAllocator: Released port block $port-${port+1}");
    }
  }

  Future<bool> _isPortFree(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }
}
