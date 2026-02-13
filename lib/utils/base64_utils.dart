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
      while (processed.length % 4 != 0) {
        processed += '=';
      }

      return utf8.decode(base64Decode(processed));
    } catch (e) {
      AdvancedLogger.warn("Base64Utils: Failed to decode string. Error: $e");
      return returnOriginalOnFail ? input : "";
    }
  }

  /// Checks if a string is likely Base64 encoded
  static bool isBase64(String input) {
    try {
      safeDecode(input);
      return true;
    } catch (e) {
      return false;
    }
  }
}
