import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/connectivity_utils.dart';
import 'package:fake_async/fake_async.dart';

// Create a Fake InternetAddress for testing
class FakeInternetAddress extends Fake implements InternetAddress {
  final String _rawAddress;
  FakeInternetAddress(this._rawAddress);

  @override
  Uint8List get rawAddress => Uint8List.fromList(_rawAddress.codeUnits);
}

void main() {
  group('ConnectivityUtils.hasInternet', () {
    test('returns true when lookup returns a valid address', () async {
      final addresses = [FakeInternetAddress('8.8.8.8')];

      final result = await ConnectivityUtils.hasInternet(
        lookup: (host) async => addresses,
      );

      expect(result, isTrue);
    });

    test('returns false when lookup throws an exception', () async {
      final result = await ConnectivityUtils.hasInternet(
        lookup: (host) async {
          throw const SocketException('Network is unreachable');
        },
      );

      expect(result, isFalse);
    });

    test('returns false when lookup returns an empty list', () async {
      final result = await ConnectivityUtils.hasInternet(
        lookup: (host) async => [],
      );

      expect(result, isFalse);
    });

    test(
      'returns false when lookup returns list with empty rawAddress',
      () async {
        final addresses = [FakeInternetAddress('')];

        final result = await ConnectivityUtils.hasInternet(
          lookup: (host) async => addresses,
        );

        expect(result, isFalse);
      },
    );

    test('returns false when lookup times out', () {
      fakeAsync((async) {
        bool? result;
        ConnectivityUtils.hasInternet(
          lookup: (host) async {
            await Future.delayed(const Duration(seconds: 4));
            return [FakeInternetAddress('8.8.8.8')];
          },
        ).then((v) => result = v);

        // Advance past the 3-second timeout
        async.elapse(const Duration(seconds: 4));
        expect(result, isFalse);
      });
    });
  });
}
