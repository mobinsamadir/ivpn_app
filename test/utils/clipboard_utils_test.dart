import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/utils/clipboard_utils.dart';

void main() {
  group('ClipboardUtils', () {
    group('detectFormat', () {
      test('should correctly identify standard formats', () {
        expect(ClipboardUtils.detectFormat('vmess://something'), equals('vmess'));
        expect(ClipboardUtils.detectFormat('vless://something'), equals('vless'));
        expect(ClipboardUtils.detectFormat('ss://something'), equals('shadowsocks'));
        expect(ClipboardUtils.detectFormat('trojan://something'), equals('trojan'));
      });

      test('should correctly identify subscriptions and URLs', () {
        expect(ClipboardUtils.detectFormat('https://example.com/subscribe'), equals('subscription'));
        expect(ClipboardUtils.detectFormat('http://example.com/sub/user'), equals('subscription'));
        expect(ClipboardUtils.detectFormat('https://example.com/something'), equals('url'));
        expect(ClipboardUtils.detectFormat('http://example.com'), equals('url'));
      });

      test('should be resilient to whitespace', () {
        expect(ClipboardUtils.detectFormat('  vmess://something  '), equals('vmess'));
        expect(ClipboardUtils.detectFormat('\tvless://something\n'), equals('vless'));
      });

      test('should default to unknown for empty or malformed strings', () {
        expect(ClipboardUtils.detectFormat(''), equals('unknown'));
        expect(ClipboardUtils.detectFormat('   '), equals('unknown'));
        expect(ClipboardUtils.detectFormat('unknown://something'), equals('unknown'));
        expect(ClipboardUtils.detectFormat('just_some_random_text'), equals('unknown'));
      });

      test('should identify case-insensitive protocols', () {
        expect(ClipboardUtils.detectFormat('VMESS://something'), equals('vmess'));
        expect(ClipboardUtils.detectFormat('vLess://something'), equals('vless'));
        expect(ClipboardUtils.detectFormat('SS://something'), equals('shadowsocks'));
        expect(ClipboardUtils.detectFormat('Trojan://something'), equals('trojan'));
      });

      test('should identify partial or incomplete valid URI strings', () {
        expect(ClipboardUtils.detectFormat('vmess://'), equals('vmess'));
        expect(ClipboardUtils.detectFormat('ss://'), equals('shadowsocks'));
      });
    });

    group('validateConfig', () {
      test('should validate successful format strings', () {
        // vmess
        expect(ClipboardUtils.validateConfig('vmess://eyJhZGRyZXNzIjoiZXhhbXBsZS5jb20ifQ=='), isTrue); // eyJhZGRyZXNzIjoiZXhhbXBsZS5jb20ifQ== is {"address":"example.com"}
        // vless
        expect(ClipboardUtils.validateConfig('vless://uuid@example.com:443'), isTrue);
        // shadowsocks
        expect(ClipboardUtils.validateConfig('ss://method:password@example.com:443'), isTrue);
        // trojan
        expect(ClipboardUtils.validateConfig('trojan://password@example.com:443'), isTrue);
        // subscription
        expect(ClipboardUtils.validateConfig('https://example.com/sub'), isTrue);
        // url
        expect(ClipboardUtils.validateConfig('https://example.com'), isTrue);
      });

      test('should fail validation for empty payloads', () {
        expect(ClipboardUtils.validateConfig('vmess://'), isFalse);
        expect(ClipboardUtils.validateConfig('vless://'), isFalse);
        expect(ClipboardUtils.validateConfig('ss://'), isFalse);
        expect(ClipboardUtils.validateConfig('trojan://'), isFalse);
      });

      test('should fail validation for malformed vmess base64', () {
        expect(ClipboardUtils.validateConfig('vmess://invalid_base64!@#'), isFalse);
      });

      test('should fail validation for malformed urls', () {
        expect(ClipboardUtils.validateConfig('https://'), isFalse); // Host is empty
        expect(ClipboardUtils.validateConfig('http://'), isFalse); // Host is empty
      });

      test('should fail validation for unknown format', () {
        expect(ClipboardUtils.validateConfig('unknown://stuff'), isFalse);
        expect(ClipboardUtils.validateConfig('some random text'), isFalse);
        expect(ClipboardUtils.validateConfig(''), isFalse);
        expect(ClipboardUtils.validateConfig('   '), isFalse);
      });
    });
  });
}
