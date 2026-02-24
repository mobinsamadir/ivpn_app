import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/advanced_logger.dart';
import '../widgets/update_dialog.dart';
import 'config_manager.dart';
import 'config_parser.dart';

class ConfigGistService {
  static final ConfigGistService _instance = ConfigGistService._internal();
  factory ConfigGistService() => _instance;
  ConfigGistService._internal();

  static const String _lastFetchKey = 'last_config_fetch_timestamp';
  static const String _backupConfigsKey = 'gist_backup_configs';
  static const Duration _fetchInterval = Duration(hours: 24);
  static const String _updateUrl = 'https://raw.githubusercontent.com/mobinsamadir/ivpn-servers/refs/heads/main/version.json';

  // Mirrors List (GitHub -> Gist -> MyFiles -> Drive API)
  static const List<String> _mirrors = [
    'https://raw.githubusercontent.com/mobinsamadir/ivpn-servers/refs/heads/main/servers.txt',
    'https://gist.githubusercontent.com/mobinsamadir/687a7ef199d6eaf6d1912e36151a9327/raw/servers.txt',
  ];

  Future<void> checkForUpdates(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      AdvancedLogger.info("[UpdateCheck] Checking for updates... Current Build: $currentBuild");

      final response = await http.get(Uri.parse(_updateUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestBuild = data['version_code'] as int;
        final version = data['version_name'] as String;
        final notes = data['release_notes'] as String? ?? 'Bug fixes and performance improvements.';
        final downloadUrl = data['download_url'] as String;

        AdvancedLogger.info("[UpdateCheck] Remote Build: $latestBuild");

        if (latestBuild > currentBuild) {
           if (context.mounted) {
             showDialog(
               context: context,
               barrierDismissible: false,
               builder: (ctx) => UpdateDialog(
                 version: version,
                 releaseNotes: notes,
                 onUpdate: () {
                    launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication);
                 },
               ),
             );
           }
        }
      }
    } catch (e) {
      AdvancedLogger.warn("[UpdateCheck] Failed: $e");
    }
  }

  Future<bool> fetchAndApplyConfigs(ConfigManager manager, {bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetchTs = prefs.getInt(_lastFetchKey) ?? 0;
    final lastFetch = DateTime.fromMillisecondsSinceEpoch(lastFetchTs);
    final now = DateTime.now();

    // Smart Logic: Fetch if FORCED OR (Empty List) OR (Time > 24h)
    if (!force && manager.allConfigs.isNotEmpty && now.difference(lastFetch) < _fetchInterval) {
       AdvancedLogger.info("[ConfigGistService] Skipping fetch. Last fetch: $lastFetch");
       return true; // Consider success as we have configs
    }

    AdvancedLogger.info("[ConfigGistService] Starting fetch (Force: $force)...");

    bool success = false;
    for (var url in _mirrors) {
      if (success) break;
      try {
        final content = await _robustFetch(url);
        if (content != null && content.isNotEmpty) {
           // Parse in background
           try {
             final configs = await compute(parseConfigsInIsolate, content);

             if (configs.isNotEmpty) {
                // Sanitize
                final cleaned = configs.map((c) {
                   return c.replaceAll(RegExp(r'"spider_x":\s*("[^"]*"|[^,{}]+),?'), '');
                }).toList();

                // Add to Manager
                final added = await manager.addConfigs(cleaned, checkBlacklist: true);
                if (added > 0) {
                   AdvancedLogger.info("[ConfigGistService] Added $added configs from $url");
                   success = true;
                   // Save for fail-safe
                   await prefs.setString(_backupConfigsKey, jsonEncode(cleaned));
                }
             }
           } catch (parseError) {
             AdvancedLogger.error("APP_ERROR: Parsing failed: $parseError");
           }
        }
      } catch (e) {
        AdvancedLogger.warn("[ConfigGistService] Mirror failed: $url - $e");
      }
    }

    if (success) {
      await prefs.setInt(_lastFetchKey, now.millisecondsSinceEpoch);
      AdvancedLogger.info("[ConfigGistService] Fetch complete. Timestamp updated.");
      return true;
    } else {
      AdvancedLogger.error("[ConfigGistService] All mirrors failed.");

      // Fail-safe
      final backupJson = prefs.getString(_backupConfigsKey);
      if (backupJson != null && backupJson.isNotEmpty) {
          try {
             final List<dynamic> rawList = jsonDecode(backupJson);
             final List<String> backupConfigs = rawList.map((e) => e.toString()).toList();

             if (backupConfigs.isNotEmpty) {
                 AdvancedLogger.warn("⚠️ Network failure. Using last known good configuration.");
                 final added = await manager.addConfigs(backupConfigs, checkBlacklist: true);
                 AdvancedLogger.info("[ConfigGistService] Restored $added configs from backup.");
                 return true; // Success via backup
             }
          } catch (e) {
             AdvancedLogger.error("APP_ERROR: Failed to load backup: $e");
          }
      }
      return false; // Total failure
    }
  }

  Future<String?> _robustFetch(String url) async {
    String targetUrl = url;

    // 1. Auto-convert Google Drive /view links
    if (targetUrl.contains('drive.google.com') && targetUrl.contains('/view')) {
        final fileIdMatch = RegExp(r'\/d\/([a-zA-Z0-9_-]+)').firstMatch(targetUrl);
        if (fileIdMatch != null) {
          final fileId = fileIdMatch.group(1);
          targetUrl = 'https://drive.google.com/uc?export=download&id=$fileId';
        }
    }

    try {
      final response = await http.get(
        Uri.parse(targetUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 15)); // strict 15-second timeout

      if (response.statusCode != 200) return null;

      String content = response.body;

      // 2. Google Drive Warning Check
      if (targetUrl.contains('drive.google.com') &&
          (content.contains('confirm=') || content.contains('Virus scan warning'))) {

          final confirmToken = _extractDriveToken(content);
          if (confirmToken != null) {
             final fileIdMatch = RegExp(r'id=([a-zA-Z0-9_-]+)').firstMatch(targetUrl);
             final fileId = fileIdMatch?.group(1);
             if (fileId != null) {
                final confirmUrl = 'https://drive.google.com/uc?export=download&id=$fileId&confirm=$confirmToken';
                final retryResponse = await http.get(Uri.parse(confirmUrl));
                if (retryResponse.statusCode == 200) content = retryResponse.body;
             }
          }
      }

      return content;
    } catch (e) {
      AdvancedLogger.warn("Fetch failed for $url: $e");
      return null;
    }
  }

  String? _extractDriveToken(String html) {
     try {
       final document = html_parser.parse(html);
       final anchors = document.querySelectorAll('a[href*="confirm="]');
       for (var a in anchors) {
          final uri = Uri.parse(a.attributes['href']!);
          if (uri.queryParameters.containsKey('confirm')) return uri.queryParameters['confirm'];
       }
     } catch (_) {}
     return null;
  }
}
