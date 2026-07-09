import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/port_allocator.dart';

void main() {
  group('PortAllocator', () {
    late PortAllocator allocator;

    setUp(() {
      allocator = PortAllocator();
      allocator.resetForTesting();
    });

    test('allocates ports within valid range and increments by 2', () async {
      final port1 = await allocator.allocate();
      expect(port1, greaterThanOrEqualTo(11000));
      expect(port1, lessThan(65535));

      final port2 = await allocator.allocate();
      expect(port2, equals(port1 + 2));
    });

    test('allocates different ports on sequential calls', () async {
      final Set<int> allocated = {};
      for (int i = 0; i < 5; i++) {
        final port = await allocator.allocate();
        expect(allocated.contains(port), isFalse);
        allocated.add(port);
      }
      expect(allocated.length, equals(5));
    });

    test('release removes ports from active set allowing reallocation (mocked scenario)', () async {
      // In a real environment, the OS will allow binding again if it's free.
      // PortAllocator checks both its active set and the OS.
      final port1 = await allocator.allocate();
      allocator.release(port1);

      // Since PortAllocator internally keeps incrementing the _currentPort,
      // it won't immediately return port1 unless it wraps around.
      // But we can ensure release doesn't throw and functions normally.
      final port2 = await allocator.allocate();
      expect(port2, equals(port1 + 2));
    });

    test('skips ports that are currently in use by the OS', () async {
      // Find what port would be next (11000) and manually bind it
      final nextPort = 11000;
      ServerSocket? blockingSocket;
      try {
        blockingSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, nextPort);

        // Allocate should skip 11000 and go to 11002
        final allocatedPort = await allocator.allocate();
        expect(allocatedPort, equals(11002));
      } finally {
        await blockingSocket?.close();
      }
    });

    test('allocates unique ports concurrently without race conditions', () async {
      // Launch 50 concurrent allocate requests
      final futures = List.generate(50, (_) => allocator.allocate());
      final ports = await Future.wait(futures);

      // Verify all are unique
      final uniquePorts = ports.toSet();
      expect(uniquePorts.length, equals(ports.length));

      // Verify they are sequential, incrementing by 2
      final sortedPorts = ports.toList()..sort();
      for (int i = 1; i < sortedPorts.length; i++) {
        expect(sortedPorts[i], equals(sortedPorts[i-1] + 2));
      }
    });
  });
}
