import 'dart:async';
import 'dart:io';
import 'package:meta/meta.dart';
import 'advanced_logger.dart';

class PortAllocator {
  static final PortAllocator _instance = PortAllocator._internal();
  factory PortAllocator() => _instance;
  PortAllocator._internal();

  static const int _startPort = 11000;
  static const int _maxPort = 65535;
  int _currentPort = _startPort;

  final Set<int> _activePorts = {};

  // Mutex lock to prevent race conditions during allocation
  bool _isAllocating = false;
  final List<Completer<void>> _allocationQueue = [];

  Future<void> _acquireLock() async {
    if (!_isAllocating) {
      _isAllocating = true;
      return;
    }
    final completer = Completer<void>();
    _allocationQueue.add(completer);
    await completer.future;
  }

  void _releaseLock() {
    if (_allocationQueue.isNotEmpty) {
      final next = _allocationQueue.removeAt(0);
      next.complete();
    } else {
      _isAllocating = false;
    }
  }

  Future<int> allocate() async {
    await _acquireLock();
    try {
      int attempts = 0;
      while (attempts < 1000) {
        if (_currentPort > _maxPort - 1) {
          _currentPort = _startPort;
        }

        int port = _currentPort;
        _currentPort += 2; // Reserve 2 ports for next call

        // Check if either port is known to be active in OUR memory
        if (_activePorts.contains(port) || _activePorts.contains(port + 1)) {
          attempts++;
          continue;
        }

        // We eagerly mark them as active to prevent another allocation from stealing them
        // if another isolate or somehow the event loop yields, but our lock already prevents that.
        // Still, good practice.
        _activePorts.add(port);
        _activePorts.add(port + 1);

        // Check if both ports are free at OS level
        if (await _isPortFree(port) && await _isPortFree(port + 1)) {
          AdvancedLogger.info(
            "PortAllocator: Allocated port block $port-${port + 1}",
          );
          return port;
        }

        // Not free at OS level, release from memory and try next
        _activePorts.remove(port);
        _activePorts.remove(port + 1);
        attempts++;
      }

      throw Exception(
        "PortAllocator: Failed to find a free port block after 1000 attempts",
      );
    } finally {
      _releaseLock();
    }
  }

  void release(int port) {
    if (_activePorts.contains(port) || _activePorts.contains(port + 1)) {
      _activePorts.remove(port);
      _activePorts.remove(port + 1);
      AdvancedLogger.info(
        "PortAllocator: Released port block $port-${port + 1}",
      );
    }
  }

  Future<bool> _isPortFree(int port) async {
    try {
      // Trying to bind to check availability
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _currentPort = _startPort;
    _activePorts.clear();
    _isAllocating = false;
    for (final completer in _allocationQueue) {
      if (!completer.isCompleted) {
        completer.completeError('PortAllocator reset for testing');
      }
    }
    _allocationQueue.clear();
  }
}
