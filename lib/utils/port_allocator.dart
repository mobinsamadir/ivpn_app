import 'dart:async';
import 'dart:io';
import 'advanced_logger.dart';

class PortAllocator {
  static final PortAllocator _instance = PortAllocator._internal();
  factory PortAllocator() => _instance;
  PortAllocator._internal();

  // Start at 20000 as requested
  static const int _startPort = 20000;
  static const int _maxPort = 65535;
  int _currentPort = _startPort;

  final Set<int> _activePorts = {};

  Future<int> allocate() async {
    // Basic loop to find next available port
    // We increment _currentPort globally to avoid re-using ports too quickly
    // even if they are released.

    int attempts = 0;
    while (attempts < 1000) {
      int port = 20000;
      synchronized(() {
        if (_currentPort > _maxPort) {
          _currentPort = _startPort;
        }
        port = _currentPort++;
      });

      if (_activePorts.contains(port)) {
        attempts++;
        continue;
      }

      if (await _isPortFree(port)) {
        _activePorts.add(port);
        AdvancedLogger.info("PortAllocator: Allocated port $port");
        return port;
      }

      attempts++;
    }

    throw Exception("PortAllocator: Failed to find a free port after 1000 attempts");
  }

  void release(int port) {
    if (_activePorts.contains(port)) {
      _activePorts.remove(port);
      AdvancedLogger.info("PortAllocator: Released port $port");
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

  // Simple synchronization helper
  void synchronized(void Function() action) {
     // In Dart, code is single-threaded within an isolate, but async gaps exist.
     // However, the critical section here (reading/writing _currentPort)
     // is synchronous, so no race condition within the same isolate.
     action();
  }
}
