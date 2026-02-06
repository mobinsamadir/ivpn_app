import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Test HTTP through sing-box proxy', () async {
    // Use a fixed port for testing - start sing-box manually first
    const httpPort = 20809; // Standard test port from config
    
    print('\n🔍 Testing HTTP Proxy Connection');
    print('📡 Proxy: 127.0.0.1:$httpPort\n');
    
    final client = HttpClient();
    
    // Configure proxy
    client.findProxy = (uri) {
      print('🔗 Using proxy for: $uri');
      return "PROXY 127.0.0.1:$httpPort;";
    };
    
    // Increase timeouts
    client.connectionTimeout = const Duration(seconds: 10);
    client.idleTimeout = const Duration(seconds: 5);
    client.userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
    
    // Test multiple endpoints
    final endpoints = [
      'http://www.gstatic.com/generate_204',
      'http://httpbin.org/get',
      'http://www.google.com',
    ];
    
    for (final endpoint in endpoints) {
      print('\n🧪 Testing: $endpoint');
      try {
        final request = await client.getUrl(Uri.parse(endpoint));
        request.headers.add('Accept', '*/*');
        request.headers.add('Connection', 'keep-alive');
        
        final response = await request.close();
        print('✅ Status: ${response.statusCode}');
        
        if (response.statusCode == 200 || response.statusCode == 204) {
          print('✅ SUCCESS - Proxy is working!');
          expect(response.statusCode, anyOf(200, 204));
          client.close();
          return; // Test passed
        }
      } catch (e) {
        print('❌ Error: $e');
      }
    }
    
    client.close();
    fail('All endpoints failed - proxy not working');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
