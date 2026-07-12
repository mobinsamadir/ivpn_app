import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/clipboard_utils.dart';
import 'dart:convert';

void main() {
  group('ClipboardUtils', () {
    group('detectFormat', () {
      test('should correctly identify standard formats', () {
        expect(
          ClipboardUtils.detectFormat('vmess://something'),
          equals('vmess'),
        );
        expect(
          ClipboardUtils.detectFormat('vless://something'),
          equals('vless'),
        );
        expect(
          ClipboardUtils.detectFormat('ss://something'),
          equals('shadowsocks'),
        );
        expect(
          ClipboardUtils.detectFormat('trojan://something'),
          equals('trojan'),
        );
      });

      test('should correctly identify subscriptions and URLs', () {
        expect(
          ClipboardUtils.detectFormat('https://example.com/subscribe'),
          equals('subscription'),
        );
        expect(
          ClipboardUtils.detectFormat('http://example.com/sub/user'),
          equals('subscription'),
        );
        expect(
          ClipboardUtils.detectFormat('https://example.com/something'),
          equals('url'),
        );
        expect(
          ClipboardUtils.detectFormat('http://example.com'),
          equals('url'),
        );
      });

      test('should be resilient to whitespace', () {
        expect(
          ClipboardUtils.detectFormat('  vmess://something  '),
          equals('vmess'),
        );
        expect(
          ClipboardUtils.detectFormat('\tvless://something\n'),
          equals('vless'),
        );
      });

      test('should default to unknown for empty or malformed strings', () {
        expect(ClipboardUtils.detectFormat(''), equals('unknown'));
        expect(ClipboardUtils.detectFormat('   '), equals('unknown'));
        expect(
          ClipboardUtils.detectFormat('unknown://something'),
          equals('unknown'),
        );
        expect(
          ClipboardUtils.detectFormat('just_some_random_text'),
          equals('unknown'),
        );
      });

      test('should identify case-insensitive protocols', () {
        expect(
          ClipboardUtils.detectFormat('VMESS://something'),
          equals('vmess'),
        );
        expect(
          ClipboardUtils.detectFormat('vLess://something'),
          equals('vless'),
        );
        expect(
          ClipboardUtils.detectFormat('SS://something'),
          equals('shadowsocks'),
        );
        expect(
          ClipboardUtils.detectFormat('Trojan://something'),
          equals('trojan'),
        );
      });

      test('should identify partial or incomplete valid URI strings', () {
        expect(ClipboardUtils.detectFormat('vmess://'), equals('vmess'));
        expect(ClipboardUtils.detectFormat('ss://'), equals('shadowsocks'));
      });
    });

    group('validateConfig', () {
      test('validates valid vmess configs', () {
        final validBase64 = base64Encode(utf8.encode('{"v":"2"}'));
        expect(
          ClipboardUtils.validateConfig('vmess://$validBase64'),
          isTrue,
          reason: 'Valid base64 vmess config should return true',
        );
      });

      test('invalidates vmess with invalid base64 content', () {
        expect(
          ClipboardUtils.validateConfig('vmess://not-a-valid-base64-string!@#'),
          isFalse,
          reason: 'Invalid base64 string should return false',
        );
      });

      test('invalidates vmess with empty content', () {
        expect(
          ClipboardUtils.validateConfig('vmess://'),
          isFalse,
          reason: 'Empty vmess config should return false',
        );
      });

      test('validates valid vless configs', () {
        expect(
          ClipboardUtils.validateConfig('vless://uuid@host:port'),
          isTrue,
          reason: 'Valid vless config should return true',
        );
      });

      test('invalidates vless with no content after scheme', () {
        expect(
          ClipboardUtils.validateConfig('vless://'),
          isFalse,
          reason: 'vless with no content should return false',
        );
      });

      test('validates valid shadowsocks configs', () {
        expect(
          ClipboardUtils.validateConfig('ss://method:password@host:port'),
          isTrue,
          reason: 'Valid ss config should return true',
        );
      });

      test('invalidates shadowsocks with no content after scheme', () {
        expect(
          ClipboardUtils.validateConfig('ss://'),
          isFalse,
          reason: 'ss with no content should return false',
        );
      });

      test('validates valid trojan configs', () {
        expect(
          ClipboardUtils.validateConfig('trojan://password@host:port'),
          isTrue,
          reason: 'Valid trojan config should return true',
        );
      });

      test('invalidates trojan with no content after scheme', () {
        expect(
          ClipboardUtils.validateConfig('trojan://'),
          isFalse,
          reason: 'trojan with no content should return false',
        );
      });

      test('validates valid subscription URLs', () {
        expect(
          ClipboardUtils.validateConfig('https://example.com/subscribe'),
          isTrue,
          reason: 'Valid subscription URL should return true',
        );
      });

      test('invalidates subscription URLs missing a host', () {
        expect(
          ClipboardUtils.validateConfig('https://'),
          isFalse,
          reason: 'URL missing host should return false',
        );
      });

      test('validates standard URLs', () {
        expect(
          ClipboardUtils.validateConfig('http://example.com/config'),
          isTrue,
          reason: 'Valid http URL should return true',
        );
      });

      test('invalidates standard URLs missing a host', () {
        expect(
          ClipboardUtils.validateConfig('http://'),
          isFalse,
          reason: 'URL missing host should return false',
        );
      });

      test('invalidates unknown schemes and text', () {
        expect(
          ClipboardUtils.validateConfig('ftp://example.com'),
          isFalse,
          reason: 'Unsupported scheme should return false',
        );
        expect(ClipboardUtils.validateConfig('unknown://stuff'), isFalse);
        expect(ClipboardUtils.validateConfig('some random text'), isFalse);
      });

      test('invalidates empty and whitespace-only strings', () {
        expect(
          ClipboardUtils.validateConfig(''),
          isFalse,
          reason: 'Empty string should return false',
        );
        expect(
          ClipboardUtils.validateConfig('   '),
          isFalse,
          reason: 'Whitespace-only string should return false',
        );
      });

      test('trims whitespace and validates valid configs correctly', () {
        final validBase64 = base64Encode(utf8.encode('test'));
        expect(
          ClipboardUtils.validateConfig('   vmess://$validBase64   '),
          isTrue,
          reason: 'Valid padded vmess should return true',
        );
        expect(
          ClipboardUtils.validateConfig('\tvless://content\n'),
          isTrue,
          reason: 'Valid padded vless should return true',
        );
      });
    });
  });
}
