import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/port_allocator.dart';

void main() {
  group('PortAllocator', () {
    late PortAllocator portAllocator;

    setUp(() {
      portAllocator = PortAllocator();
      portAllocator.resetForTesting();
    });

    tearDown(() {
      portAllocator.resetForTesting();
    });

    test('allocates ports within valid range and increments by 2', () async {
      final port1 = await portAllocator.allocate();
      expect(port1, greaterThanOrEqualTo(11000));
      expect(port1, lessThan(65535));

      final port2 = await portAllocator.allocate();
      expect(port2, equals(port1 + 2));
    });

    test('allocates different ports on sequential calls', () async {
      final Set<int> allocated = {};
      for (int i = 0; i < 5; i++) {
        final port = await portAllocator.allocate();
        expect(allocated.contains(port), isFalse);
        allocated.add(port);
      }
      expect(allocated.length, equals(5));
    });

    test('should successfully release ports', () async {
      final port1 = await portAllocator.allocate();
      portAllocator.release(port1);

      // Verify normal operation continues after release
      final port2 = await portAllocator.allocate();
      expect(port2, equals(port1 + 2));
    });

    test('skips ports that are currently in use by the OS', () async {
      final nextPort = 11000;
      ServerSocket? blockingSocket;
      try {
        blockingSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, nextPort);

        final allocatedPort = await portAllocator.allocate();
        expect(allocatedPort, equals(11002));
      } finally {
        await blockingSocket?.close();
      }
    });

    test('allocates unique ports concurrently without race conditions', () async {
      // Launch 50 concurrent allocate requests
      final futures = List.generate(50, (_) => portAllocator.allocate());
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

    test('should throw Exception when retry limit is exhausted', () async {
      // Mock ServerSocket.bind to always throw, causing _isPortFree to return false
      await IOOverrides.runZoned(
        () async {
          expect(
            () async => await portAllocator.allocate(),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('PortAllocator: Failed to find a free port block after 1000 attempts'),
              ),
            ),
          );
        },
        serverSocketBind: (address, port, {backlog = 0, shared = false, v6Only = false}) {
          throw const SocketException('Mock connection refused');
        },
      );
    });
  });
}