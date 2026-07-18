import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ivpn_new/services/time_wallet_service.dart';

class MockHttpOverrides extends HttpOverrides {
  final bool failNetwork;
  final bool missingDate;

  MockHttpOverrides({this.failNetwork = false, this.missingDate = false});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockHttpClient(failNetwork: failNetwork, missingDate: missingDate);
  }
}

class MockHttpClient implements HttpClient {
  final bool failNetwork;
  final bool missingDate;
  @override
  Duration? connectionTimeout;

  Duration idleTimeout = const Duration(seconds: 15);
  @override
  bool autoUncompress = true;
  @override
  Duration? maxConnectionAge;
  @override
  String? userAgent;

  MockHttpClient({this.failNetwork = false, this.missingDate = false});

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (failNetwork) {
      throw const SocketException("Network failed");
    }
    return MockHttpClientRequest(missingDate: missingDate);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpClientRequest implements HttpClientRequest {
  final bool missingDate;

  MockHttpClientRequest({this.missingDate = false});

  @override
  Future<HttpClientResponse> close() async {
    return MockHttpClientResponse(missingDate: missingDate);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpClientResponse implements HttpClientResponse {
  final bool missingDate;

  MockHttpClientResponse({this.missingDate = false});

  @override
  HttpHeaders get headers => MockHttpHeaders(missingDate: missingDate);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpHeaders implements HttpHeaders {
  final bool missingDate;

  MockHttpHeaders({this.missingDate = false});

  @override
  String? value(String name) {
    if (name.toLowerCase() == 'date') {
      if (missingDate) return null;
      return HttpDate.format(DateTime.now().toUtc());
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimeWalletService Tests', () {
    late TimeWalletService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      HttpOverrides.global = MockHttpOverrides();
      service = TimeWalletService();
    });

    tearDown(() {
      HttpOverrides.global = null;
    });

    test('currentSecureTime fallback when not initialized', () {
      final time = service.currentSecureTime;
      expect(time, isNotNull);
    });

    test('Initial state should have 0 remaining seconds', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init();
      // Calling init twice to hit the early return
      await service.init();
      expect(service.hasTime, isFalse);
      expect(service.remainingSeconds, equals(0));
    });

    test('rewardTime adds 1 hour to the wallet', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init();

      await service.consumeTime(service.remainingSeconds + 100);

      await service.rewardTime();
      expect(service.hasTime, isTrue);
      expect(service.remainingSeconds, inInclusiveRange(3590, 3600));
    });

    test('consumeTime reduces time correctly', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init();

      await service.consumeTime(service.remainingSeconds + 100);
      await service.rewardTime();

      await service.consumeTime(1800);
      expect(service.remainingSeconds, inInclusiveRange(1790, 1800));
    });

    test('consumeTime to zero or below triggers expiration', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init();

      await service.consumeTime(service.remainingSeconds + 100);
      await service.rewardTime();

      await service.consumeTime(4000);
      expect(service.hasTime, isFalse);
      expect(service.remainingSeconds, equals(0));
    });

    test('syncNetworkTime success sets network time', () async {
      HttpOverrides.global =
          MockHttpOverrides(failNetwork: false, missingDate: false);
      await service.init();
      await service.syncNetworkTime();
      expect(service.currentSecureTime, isNotNull);
    });

    test('syncNetworkTime network failure falls back to local clock', () async {
      HttpOverrides.global = MockHttpOverrides(failNetwork: true);
      await service.syncNetworkTime();
      expect(service.currentSecureTime, isNotNull);
    });

    test('syncNetworkTime missing date header throws and falls back', () async {
      HttpOverrides.global = MockHttpOverrides(missingDate: true);
      await service.syncNetworkTime();
      expect(service.currentSecureTime, isNotNull);
    });

    test('timer logic covers hasTime and !hasTime', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init();

      // Ensure no time left
      await service.consumeTime(service.remainingSeconds + 100);

      bool notified = false;
      service.addListener(() {
        notified = true;
      });

      // Grant exactly 1 second, then wait 2 seconds for timer to expire it
      await service.rewardTime();
      await service.consumeTime(3599);

      // Wait for timer to tick 2 times
      await Future.delayed(const Duration(seconds: 2));

      expect(notified, isTrue);
      expect(service.hasTime, isFalse);
    });

    test('dispose cancels timers', () async {
      service.dispose();
    });
  });
}
