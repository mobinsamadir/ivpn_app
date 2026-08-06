import 'dart:convert';
import 'advanced_logger.dart';

class Base64Utils {
  /// Safely decodes a Base64 string, handling padding issues and URL-safe characters.
  /// If decoding fails, it returns the original string or an empty string based on [returnOriginalOnFail].
  static String safeDecode(String input, {bool returnOriginalOnFail = false}) {
    if (input.isEmpty) return "";

    try {
      String processed = input.trim();

      // Remove whitespace
      processed = processed.replaceAll(RegExp(r'\s+'), '');

      // Normalize URL-safe characters
      processed = processed.replaceAll('-', '+').replaceAll('_', '/');

      // Fix Padding
      if (processed.length % 4 != 0) {
        processed = processed.padRight(
          processed.length + (4 - processed.length % 4),
          '=',
        );
      }

      return utf8.decode(base64Decode(processed));
    } catch (e) {
      AdvancedLogger.warn("Base64Utils: Failed to decode string. Error: $e");
      return returnOriginalOnFail ? input : "";
    }
  }

  /// Checks if a string is likely Base64 encoded
  static bool isBase64(String input) {
    if (input.isEmpty) return false;

    String processed = input.trim().replaceAll(RegExp(r'\s+'), '');
    processed = processed.replaceAll('-', '+').replaceAll('_', '/');

    // Remove valid padding
    processed = processed.replaceAll(RegExp(r'=+$'), '');

    // Base64 must have a valid length
    if (processed.length % 4 == 1) return false;

    // Check for invalid characters using regex
    final validBase64 = RegExp(r'^[a-zA-Z0-9+/]+$');
    if (!validBase64.hasMatch(processed)) return false;

    try {
      // Fix Padding
      if (processed.length % 4 != 0) {
        processed = processed.padRight(
          processed.length + (4 - processed.length % 4),
          '=',
        );
      }

      base64Decode(processed);
      return true;
    } catch (e) {
      return false;
    }
  }
}
