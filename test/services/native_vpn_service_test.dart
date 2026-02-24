import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/native_vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel methodChannel = MethodChannel('com.example.ivpn/vpn');
  // const EventChannel eventChannel = EventChannel('com.example.ivpn/vpn_status'); // Not used directly

  late NativeVpnService service;
  final List<MethodCall> methodCalls = [];

  // Helper to create valid VMess
  String createValidVmess() {
    final map = {
      "v": "2",
      "ps": "Test Server",
      "add": "127.0.0.1",
      "port": "8080",
      "id": "a3482e88-6fb1-4209-9b80-1234567890ab",
      "aid": "0",
      "scy": "auto",
      "net": "tcp",
      "type": "none",
      "host": "",
      "path": "",
      "tls": "",
      "sni": "",
      "alpn": ""
    };
    final jsonStr = jsonEncode(map);
    final base64Str = base64Encode(utf8.encode(jsonStr));
    return 'vmess://$base64Str';
  }

  setUp(() {
    methodCalls.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall methodCall) async {
        methodCalls.add(methodCall);
        switch (methodCall.method) {
          case 'testConfig':
            return 100;
          case 'startVpn':
            return null;
          case 'stopVpn':
            return null;
          case 'startTestProxy':
            return 10808;
          case 'stopTestProxy':
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, null);
  });

  test('Connect calls startVpn with valid config', () async {
    service = NativeVpnService();
    final config = createValidVmess();

    await service.connect(config);

    expect(methodCalls, hasLength(1));
    expect(methodCalls.first.method, 'startVpn');
    // Verify the generated Singbox config contains expected structure
    final args = methodCalls.first.arguments as Map;
    expect(args, containsPair('config', contains('outbounds')));
  });

  test('Disconnect calls stopVpn', () async {
    service = NativeVpnService();
    await service.disconnect();

    expect(methodCalls.map((c) => c.method), contains('stopVpn'));
  });

  test('getPing returns latency', () async {
    service = NativeVpnService();
    final latency = await service.getPing('config');
    expect(latency, 100);
    expect(methodCalls.last.method, 'testConfig');
  });

  test('Status Stream emits events from Native side', () async {
    service = NativeVpnService();

    // Listen to the stream
    final future = service.connectionStatusStream.first;

    // Simulate Native Event
    const channelName = 'com.example.ivpn/vpn_status';
    const codec = StandardMethodCodec();
    final data = codec.encodeSuccessEnvelope('CONNECTED');

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channelName,
      data,
      (ByteData? data) {},
    );

    expect(await future, 'CONNECTED');
  });

  test('Error Handling: Native Error Event', () async {
    service = NativeVpnService();

    final future = service.connectionStatusStream.first;

    // Simulate Native Error
    const channelName = 'com.example.ivpn/vpn_status';
    const codec = StandardMethodCodec();
    // Simulate error envelope?
    // EventChannel errors are usually sent via `encodeErrorEnvelope`.
    final data = codec.encodeErrorEnvelope(
      code: 'NATIVE_ERR',
      message: 'Something went wrong',
      details: null
    );

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channelName,
      data,
      (ByteData? data) {},
    );

    // The service catches error and emits "ERROR: NATIVE_EVENT: ..."
    // Expecting string starting with ERROR
    final result = await future;
    expect(result, contains('ERROR: NATIVE_EVENT'));
    expect(result, contains('Something went wrong'));
  });
}
