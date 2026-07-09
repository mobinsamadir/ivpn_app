import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/connectivity_service.dart';

void main() {
  group('ConnectivityService', () {
    test('hasInternet() returns true when the checker returns true', () async {
      // Arrange
      final service = ConnectivityService(internetChecker: () async => true);

      // Act
      final result = await service.hasInternet();

      // Assert
      expect(result, isTrue);
    });

    test(
      'hasInternet() returns false when the checker returns false',
      () async {
        // Arrange
        final service = ConnectivityService(internetChecker: () async => false);

        // Act
        final result = await service.hasInternet();

        // Assert
        expect(result, isFalse);
      },
    );
  });
}
