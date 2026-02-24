import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ivpn_new/services/config_gist_service.dart';
import 'package:ivpn_new/services/config_manager.dart';

// Mocks
class MockConfigManager extends Mock implements ConfigManager {}

// Helper for Network Failure
class FailingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return FailingHttpClient();
  }
}

class FailingHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    throw const SocketException('Simulated network failure');
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return getUrl(url);
  }

  @override
  void close({bool force = false}) {}
}

// Helper for Stress Test (Success)
class SuccessHttpOverrides extends HttpOverrides {
  final String responseBody;
  SuccessHttpOverrides(this.responseBody);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return SuccessHttpClient(responseBody);
  }
}

class SuccessHttpClient extends Fake implements HttpClient {
  final String responseBody;
  SuccessHttpClient(this.responseBody);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return MockHttpClientRequest(responseBody);
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return getUrl(url);
  }

  @override
  void close({bool force = false}) {}
}

class MockHttpClientRequest extends Fake implements HttpClientRequest {
  final String responseBody;
  MockHttpClientRequest(this.responseBody);

  @override
  Future<HttpClientResponse> close() async {
    return MockHttpClientResponse(responseBody);
  }

  @override
  HttpHeaders get headers => MockHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain();
  }

  @override
  void add(List<int> data) {}

  @override
  void write(Object? obj) {}
}

class MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void removeAll(String name) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}
}

class MockHttpClientResponse extends Fake implements HttpClientResponse {
  final String responseBody;
  MockHttpClientResponse(this.responseBody);

  @override
  int get statusCode => 200;

  @override
  HttpHeaders get headers => MockHttpHeaders();

  @override
  int get contentLength => utf8.encode(responseBody).length;

  @override
  String get reasonPhrase => 'OK';

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => [];

  @override
  bool get persistentConnection => true;

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) {
    return Stream.value(utf8.encode(responseBody)).cast<List<int>>().transform(streamTransformer);
  }

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream.value(utf8.encode(responseBody)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

void main() {
  late MockConfigManager mockManager;
  late ConfigGistService service;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    mockManager = MockConfigManager();
    // Reset service singleton (not possible directly, but it's stateless except cache)
    // But ConfigGistService is a singleton.
    // It relies on SharedPreferences.
    SharedPreferences.setMockInitialValues({});
    service = ConfigGistService();

    when(() => mockManager.allConfigs).thenReturn([]);
    when(() => mockManager.addConfigs(any(), checkBlacklist: any(named: 'checkBlacklist')))
        .thenAnswer((_) async => 0);
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  test('fetchAndApplyConfigs uses backup on network failure', () async {
    HttpOverrides.global = FailingHttpOverrides();

    final backupConfigs = ['vmess://backup1', 'vless://backup2'];
    SharedPreferences.setMockInitialValues({
      'gist_backup_configs': jsonEncode(backupConfigs),
      'last_config_fetch_timestamp': 0,
    });

    when(() => mockManager.addConfigs(any(), checkBlacklist: any(named: 'checkBlacklist')))
        .thenAnswer((_) async => 2);

    await service.fetchAndApplyConfigs(mockManager, force: true);

    verify(() => mockManager.addConfigs(backupConfigs, checkBlacklist: true)).called(1);
  });

  test('Corrupted Storage Test: Handles invalid JSON backup without crashing', () async {
    HttpOverrides.global = FailingHttpOverrides();

    // Corrupted JSON
    SharedPreferences.setMockInitialValues({
      'gist_backup_configs': '{ invalid_json: "broken" ',
      'last_config_fetch_timestamp': 0,
    });

    // Should NOT throw
    await service.fetchAndApplyConfigs(mockManager, force: true);

    // Verify addConfigs was NEVER called
    verifyNever(() => mockManager.addConfigs(any(), checkBlacklist: any(named: 'checkBlacklist')));
  });

  test('Stress Test: Handles 500+ configs from network', () async {
    // Generate 500 configs
    final buffer = StringBuffer();
    for (int i = 0; i < 500; i++) {
      buffer.writeln('vmess://server_$i');
    }
    final largeBody = buffer.toString();

    HttpOverrides.global = SuccessHttpOverrides(largeBody);

    when(() => mockManager.addConfigs(any(), checkBlacklist: any(named: 'checkBlacklist')))
        .thenAnswer((invocation) async {
           final list = invocation.positionalArguments[0] as List<String>;
           return list.length;
        });

    await service.fetchAndApplyConfigs(mockManager, force: true);

    // Verify all 500 were parsed and added
    final captured = verify(() => mockManager.addConfigs(captureAny(), checkBlacklist: true)).captured;
    final addedList = captured.first as List<String>;

    expect(addedList.length, 500);
    expect(addedList.first, 'vmess://server_0');
    expect(addedList.last, 'vmess://server_499');
  });
}
