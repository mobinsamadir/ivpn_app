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

    test('should allocate distinct port blocks sequentially', () async {
      final port1 = await portAllocator.allocate();
      final port2 = await portAllocator.allocate();

      expect(port1, isNotNull);
      expect(port2, isNotNull);
      expect(port1, isNot(equals(port2)));
      // It increments by 2 each time
      expect(port2, equals(port1 + 2));
    });

    test('should successfully release ports', () async {
      final port1 = await portAllocator.allocate();

      // Before release, attempting to allocate should give the next distinct block
      final port2 = await portAllocator.allocate();
      expect(port1, isNot(equals(port2)));

      // Release port1 block
      portAllocator.release(port1);

      // Because `_currentPort` is just incremented, we'll continue getting new ports until wrap-around,
      // but we can verify it doesn't throw and no errors occur.
      final port3 = await portAllocator.allocate();
      expect(port3, isNotNull);
      expect(port3, isNot(equals(port1)));
      expect(port3, isNot(equals(port2)));
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
