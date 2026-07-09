import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/clipboard_utils.dart';
import 'dart:convert';

void main() {
  group('ClipboardUtils', () {
    group('detectFormat', () {
      test('detects vmess format', () {
        expect(ClipboardUtils.detectFormat('vmess://something'), 'vmess');
      });

      test('detects vless format', () {
        expect(ClipboardUtils.detectFormat('vless://something'), 'vless');
      });

      test('detects shadowsocks format', () {
        expect(ClipboardUtils.detectFormat('ss://something'), 'shadowsocks');
      });

      test('detects trojan format', () {
        expect(ClipboardUtils.detectFormat('trojan://something'), 'trojan');
      });

      test('detects subscription links', () {
        expect(ClipboardUtils.detectFormat('https://example.com/subscribe'), 'subscription');
        expect(ClipboardUtils.detectFormat('http://example.com/sub'), 'subscription');
        expect(ClipboardUtils.detectFormat('https://example.com/something_with_sub_in_it'), 'subscription');
      });

      test('detects standard URLs', () {
        expect(ClipboardUtils.detectFormat('https://example.com/api'), 'url');
        expect(ClipboardUtils.detectFormat('http://test.com/path'), 'url');
      });

      test('detects general URIs', () {
        expect(ClipboardUtils.detectFormat('ftp://example.com'), 'ftp');
        expect(ClipboardUtils.detectFormat('custom://data'), 'custom');
      });

      test('returns unknown for unparseable strings', () {
        expect(ClipboardUtils.detectFormat('not a uri'), 'unknown');
        expect(ClipboardUtils.detectFormat(''), 'unknown');
      });

      test('trims whitespace before detecting', () {
        expect(ClipboardUtils.detectFormat('   vmess://something   '), 'vmess');
      });
    });

    group('validateConfig', () {
      test('validates valid vmess configs', () {
        final validBase64 = base64Encode(utf8.encode('{"v":"2"}'));
        expect(ClipboardUtils.validateConfig('vmess://$validBase64'), isTrue, reason: 'Valid base64 vmess config should return true');
      });

      test('invalidates vmess with invalid base64 content', () {
        expect(ClipboardUtils.validateConfig('vmess://not-a-valid-base64-string!@#'), isFalse, reason: 'Invalid base64 string should return false');
      });

      test('invalidates vmess with empty content', () {
        expect(ClipboardUtils.validateConfig('vmess://'), isFalse, reason: 'Empty vmess config should return false');
      });

      test('validates valid vless configs', () {
        expect(ClipboardUtils.validateConfig('vless://uuid@host:port'), isTrue, reason: 'Valid vless config should return true');
      });

      test('invalidates vless with no content after scheme', () {
        expect(ClipboardUtils.validateConfig('vless://'), isFalse, reason: 'vless with no content should return false');
      });

      test('validates valid shadowsocks configs', () {
        expect(ClipboardUtils.validateConfig('ss://method:password@host:port'), isTrue, reason: 'Valid ss config should return true');
      });

      test('invalidates shadowsocks with no content after scheme', () {
        expect(ClipboardUtils.validateConfig('ss://'), isFalse, reason: 'ss with no content should return false');
      });

      test('validates valid trojan configs', () {
        expect(ClipboardUtils.validateConfig('trojan://password@host:port'), isTrue, reason: 'Valid trojan config should return true');
      });

      test('invalidates trojan with no content after scheme', () {
        expect(ClipboardUtils.validateConfig('trojan://'), isFalse, reason: 'trojan with no content should return false');
      });

      test('validates valid subscription URLs', () {
        expect(ClipboardUtils.validateConfig('https://example.com/subscribe'), isTrue, reason: 'Valid subscription URL should return true');
      });

      test('invalidates subscription URLs missing a host', () {
        expect(ClipboardUtils.validateConfig('https://'), isFalse, reason: 'URL missing host should return false');
      });

      test('validates standard URLs', () {
        expect(ClipboardUtils.validateConfig('http://example.com/config'), isTrue, reason: 'Valid http URL should return true');
      });

      test('invalidates standard URLs missing a host', () {
        expect(ClipboardUtils.validateConfig('http://'), isFalse, reason: 'URL missing host should return false');
      });

      test('invalidates unknown schemes', () {
        expect(ClipboardUtils.validateConfig('ftp://example.com'), isFalse, reason: 'Unsupported scheme should return false');
      });

      test('invalidates empty and whitespace-only strings', () {
        expect(ClipboardUtils.validateConfig(''), isFalse, reason: 'Empty string should return false');
        expect(ClipboardUtils.validateConfig('   '), isFalse, reason: 'Whitespace-only string should return false');
      });

      test('trims whitespace and validates valid configs correctly', () {
        final validBase64 = base64Encode(utf8.encode('test'));
        expect(ClipboardUtils.validateConfig('   vmess://$validBase64   '), isTrue, reason: 'Valid padded vmess should return true');
        expect(ClipboardUtils.validateConfig('\tvless://content\n'), isTrue, reason: 'Valid padded vless should return true');
      });
    });
  });
}
