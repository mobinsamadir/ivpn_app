import 'package:flutter/services.dart';
import 'dart:convert';

class ClipboardUtils {
  static Future<String> getText() async {
    try {
      final ClipboardData? data = await Clipboard.getData('text/plain');
      return data?.text ?? '';
    } catch (e) {
      return '';
    }
  }

  static Future<void> setText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Detects the format of a config string (vmess/vless/ss/trojan)
  static String detectFormat(String config) {
    config = config.trim();
    final lowerConfig = config.toLowerCase();

    if (lowerConfig.startsWith('vmess://')) {
      return 'vmess';
    } else if (lowerConfig.startsWith('vless://')) {
      return 'vless';
    } else if (lowerConfig.startsWith('ss://')) {
      return 'shadowsocks';
    } else if (lowerConfig.startsWith('trojan://')) {
      return 'trojan';
    } else if (lowerConfig.startsWith('https://') ||
        lowerConfig.startsWith('http://')) {
      // Check if it's a subscription link
      if (lowerConfig.contains('subscribe') || lowerConfig.contains('sub')) {
        return 'subscription';
      }
      return 'url';
    } else if (_isValidUri(config)) {
      // Try to parse as a general URI format
      try {
        final uri = Uri.parse(config);
        if (uri.scheme.isNotEmpty) {
          return uri.scheme.toLowerCase();
        }
      } catch (e) {
        // Not a valid URI
      }
    }

    return 'unknown';
  }

  static bool _isValidUri(String uri) {
    try {
      Uri.parse(uri);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Validates if a config string is potentially valid
  static bool validateConfig(String config) {
    config = config.trim();

    if (config.isEmpty) return false;

    // Basic validation based on format
    switch (detectFormat(config)) {
      case 'vmess':
        // Basic vmess validation - should be a valid base64 encoded string after the prefix
        try {
          // Remove 'vmess://' prefix (case-insensitive)
          final encoded = config.substring(8);
          final decoded = base64Decode(encoded);
          return decoded.isNotEmpty;
        } catch (e) {
          return false;
        }
      case 'vless':
      case 'shadowsocks':
      case 'trojan':
        // For these, just check if there's content after the scheme
        // Case-insensitive split
        final lowerConfig = config.toLowerCase();
        final schemeEnd = lowerConfig.indexOf('://');
        if (schemeEnd == -1) return false;
        final contentAfterScheme = config.substring(schemeEnd + 3);
        return contentAfterScheme.isNotEmpty;
      case 'subscription':
      case 'url':
        // Validate as URL
        try {
          final uri = Uri.parse(config);
          return uri.hasScheme && uri.host.isNotEmpty;
        } catch (e) {
          return false;
        }
      default:
        return false;
    }
  }
}
