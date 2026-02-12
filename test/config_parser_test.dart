import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/services/config_manager.dart';

void main() {
  group('ConfigParser Tests', () {
    test('Clean Input - 3 configs separated by newline', () async {
      final input = '''vmess://config1
vless://config2
ss://config3''';
      
      final result = await ConfigManager.parseMixedContent(input);
      
      expect(result.length, 3);
      expect(result[0], 'vmess://config1=');
      expect(result[1], 'vless://config2');
      expect(result[2], 'ss://config3');
    });

    test('Dirty Input - configs with spaces, commas, and mixed newlines (Smart Paste bug scenario)', () async {
      final input = '''vmess://config1, vless://config2 , ss://config3
      trojan://config4    ss://config5''';
      
      final result = await ConfigManager.parseMixedContent(input);
      
      expect(result.length, 5);
      expect(result.contains('vmess://config1='), isTrue);
      expect(result.contains('vless://config2'), isTrue);
      expect(result.contains('ss://config3'), isTrue);
      expect(result.contains('trojan://config4='), isTrue);
      expect(result.contains('ss://config5'), isTrue);
    });

    test('Garbage Input - random text should return empty list', () async {
      final input = '''This is random text
      with no valid configs
      just garbage data
      vmess is here but not a valid url''';
      
      final result = await ConfigManager.parseMixedContent(input);
      
      expect(result.length, 0);
    });

    test('Mixed valid and invalid configs', () async {
      final input = '''vmess://validconfig1
      invalid text here
      vless://validconfig2
      not a config at all
      ss://validconfig3''';
      
      final result = await ConfigManager.parseMixedContent(input);
      
      expect(result.length, 3);
      expect(result.contains('vmess://validconfig1'), isTrue);
      expect(result.contains('vless://validconfig2'), isTrue);
      expect(result.contains('ss://validconfig3'), isTrue);
    });

    test('Empty input returns empty list', () async {
      final input = '';
      
      final result = await ConfigManager.parseMixedContent(input);
      
      expect(result.length, 0);
    });

    test('Input with only whitespace returns empty list', () async {
      final input = '   \n  \t  \r  ';
      
      final result = await ConfigManager.parseMixedContent(input);
      
      expect(result.length, 0);
    });
  });
}