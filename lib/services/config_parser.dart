import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

/// Runs in a background isolate to parse configurations without blocking the UI.
Future<List<String>> parseConfigsInIsolate(String text) async {
  final collectedConfigs = <String>{};

  String processedText = text;

  // 1. Detect & Parse HTML
  // If it looks like HTML, use the parser to get clean text (decodes entities automatically)
  if (text.trimLeft().startsWith('<') || text.contains('<!DOCTYPE html>')) {
     try {
       var document = html_parser.parse(text);
       // .text automatically decodes &amp; -> & and strips tags
       final bodyText = document.body?.text ?? '';

       // Also extract hrefs from anchor tags to catch links
       final hrefs = document.querySelectorAll('a')
           .map((e) => e.attributes['href'])
           .whereType<String>()
           .join('\n');

       processedText = '$bodyText\n$hrefs';
     } catch (e) {
       // Fallback to raw text if parsing fails
       if (kDebugMode) {
         debugPrint('[ConfigParser] HTML parsing failed: $e');
       }
     }
  }
  // 2. CHECK IF ALREADY A PROTOCOL (Before decoding)
  else if (text.trim().startsWith(RegExp(r'(vless|vmess|trojan|ss|ssr)://'))) {
     // It's already a config, do NOT decode
     processedText = text;
  }
  else {
     // 3. Base64 Decode Attempt (Only if not HTML and not already protocol)
     final decoded = _safeBase64Decode(text);
     if (decoded.isNotEmpty && decoded.contains('://')) {
        processedText = decoded;
     }
  }

  // 3. Extract Configs using RELAXED "Terminator" Regex
  // Capture everything until whitespace, <, ", ', or ` (backtick)
  final regex = RegExp(
    r'''(vless|vmess|trojan|ss):\/\/[^\s<"'`]+''',
    caseSensitive: false,
    multiLine: true,
  );

  for (final match in regex.allMatches(processedText)) {
     var rawConfig = match.group(0)?.trim();
     if (rawConfig != null && rawConfig.isNotEmpty) {
        var config = rawConfig;
        try {
           // Basic Sanitization (Remove trailing punctuation if regex overshot)
           const junkChars = {'.', ',', ')', '?', ';', '&'};
           while (config.isNotEmpty && junkChars.contains(config[config.length - 1])) {
             config = config.substring(0, config.length - 1);
           }

           if (config.contains('%')) {
              config = Uri.decodeFull(config);
           }
           collectedConfigs.add(config);
        } catch (e) {
           if (kDebugMode) {
             debugPrint("Failed to parse extracted config. Error: $e");
           }
        }
     }
  }

  return collectedConfigs.toList();
}

/// Helper: Safely decodes a Base64 string (Internal version to avoid isolate dependencies)
String _safeBase64Decode(String input) {
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
    // Return empty on failure
    return "";
  }
}
