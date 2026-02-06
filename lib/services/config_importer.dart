
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/file_logger.dart';

class ConfigImporter {
  // Regex to identify protocol fragments in a mixed blob
  // FIXED: Used double quotes for raw string because the pattern contains a single quote
  static final RegExp _protocolRegex = RegExp(
    r"(vmess|vless|trojan|ss|http|https):\/\/[a-zA-Z0-9\+\-\.\_\~\!\$\&\'\(\)\*\+\,\;\=\:\@\%\/\?\#]+",
    caseSensitive: false,
    multiLine: true,
  );

  /// Main entry point: Parses ANY text blob (Raw, Sub, Mixed).
  /// Returns a clean list of valid proxy configs (vmess/vless/ss/trojan).
  static Future<List<String>> parseInput(String rawInput, {int depth = 0}) async {
    final Set<String> validConfigs = {};

    // Safety check for recursion depth (Max 3 levels of nested subs)
    if (depth > 3) return [];

    // 1. Find and process ALL subscriptions in the text
    final urlMatches = RegExp(r'https?://[^\s]+').allMatches(rawInput);
    for (final match in urlMatches) {
      String url = match.group(0)!.trim();
      if (!_isValidProxyConfig(url)) { // It's likely a sub
         FileLogger.log("🔄 [Importer] Scanning Sub: $url");
         final subConfigs = await _fetchSubscription(url, depth: depth + 1);
         validConfigs.addAll(subConfigs);
      }
    }

    // 2. Find and process ALL direct configs
    final protocolMatches = _protocolRegex.allMatches(rawInput);
    for (final match in protocolMatches) {
      String candidate = match.group(0)?.trim() ?? "";
      if (candidate.isEmpty) continue;

      // Handle Direct Config
      if (_isValidProxyConfig(candidate)) {
          print('[IMPORTER] Found valid config: ${candidate.substring(0, candidate.length > 50 ? 50 : candidate.length)}...');
          print('[IMPORTER] Has parameters: ${candidate.contains('?')}');
          validConfigs.add(candidate);
      }
    }

    print("✅ [IMPORTER] Parsed ${validConfigs.length} unique configs.");
    FileLogger.log("✅ [Importer] Parsed ${validConfigs.length} unique configs.");
    return validConfigs.toList();
  }

  static bool _isSubscription(String link) {
    return link.toLowerCase().startsWith('http://') || 
           link.toLowerCase().startsWith('https://');
  }

  static bool _isValidProxyConfig(String link) {
    final l = link.toLowerCase();
    return l.startsWith('vmess://') || 
           l.startsWith('vless://') || 
           l.startsWith('trojan://') || 
           l.startsWith('ss://');
  }

  /// Extracts a human-readable name from a config URL (remark after #)
  static String extractName(String link, {int index = 0}) {
    try {
      final uri = Uri.parse(link.trim());
      if (uri.hasFragment && uri.fragment.isNotEmpty) {
        return Uri.decodeComponent(uri.fragment);
      }
      
      // Fallback for VMess (which is JSON base64 encoded)
      if (link.toLowerCase().startsWith('vmess://')) {
        try {
          String encoded = link.substring(8).replaceAll(RegExp(r'\s+'), '');
          // Basic base64 cleanup
          int mod = encoded.length % 4;
          if (mod > 0) encoded += '=' * (4 - mod);
          
          final decoded = utf8.decode(base64Decode(encoded));
          final data = jsonDecode(decoded);
          if (data['ps'] != null && data['ps'].toString().isNotEmpty) {
            return data['ps'].toString();
          }
        } catch (_) {}
      }
    } catch (_) {}
    
    return "Config ${index + 1}";
  }

  static Future<List<String>> _fetchSubscription(String url, {required int depth}) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        String content = utf8.decode(response.bodyBytes);
        
        // Try Base64 Decode (Standard Subscription Format)
        try {
          content = utf8.decode(base64Decode(content.replaceAll(RegExp(r'\s+'), '')));
        } catch (_) {
          // Content might be plain text list, keep as is
        }

        // Recursively parse the content of the subscription
        return await parseInput(content, depth: depth);
      }
    } catch (e) {
      FileLogger.log("❌ [Importer] Sub Fetch Error ($url): $e");
    }
    return [];
  }

  // Legacy support getter if needed elsewhere, maps to general parser
  static Future<List<String>> fetchAndParse(String input) => parseInput(input);

  /// Load initial hardcoded configurations
  static Future<List<String>> loadInitialConfigs() async {
    // These are placeholders/defaults that should always be available
    return [
      "vmess://eyJhZGQiOiI4NS4xOTUuMTAxLjEyMiIsImFpZCI6IjAiLCJhbHBuIjoiIiwiZnAiOiIiLCJob3N0IjoiIiwiaWQiOiJmM2Q0MTY3ZS1iMTVlLTRlNDYtODJlOS05Mjg2ZWY5M2ZkYTciLCJuZXQiOiJ0Y3AiLCJwYXRoIjoiIiwicG9ydCI6IjQwODc4IiwicHMiOiJJUi1ASVJBTl9WMlJBWTEiLCJzY3kiOiJhdXRvIiwic25pIjoiIiwidGxzIjoiIiwidHlwZSI6Im5vbmUiLCJ2IjoiMiJ9",
      "ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpKSWhONnJCS2thRWJvTE5YVlN2NXJx@142.4.216.225:80#All-%40IRAN_V2RAY1",
    ];
  }
}
