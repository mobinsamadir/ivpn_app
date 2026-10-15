import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/advanced_logger.dart';
import '../widgets/update_dialog.dart';
import 'config_manager.dart';
import 'config_parser.dart';
import 'network_tuning_config.dart';

dynamic _parseJson(String str) => jsonDecode(str);

class ConfigGistService {
  static final ConfigGistService _instance = ConfigGistService._internal();

  static final _spiderXRegex = RegExp(r'"spider_x":\s*("[^"]*"|[^,{}]+),?');
  factory ConfigGistService() => _instance;
  ConfigGistService._internal();

  static String telegramSupport = 'iVPN_support';
  static int rewardAdDurationSeconds = 20;

  static const String _cachedTelegramSupportKey = 'cached_telegram_support';
  static const String _cachedRewardAdDurationKey = 'cached_reward_ad_duration';

  static Future<String> getTelegramSupport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_cachedTelegramSupportKey)) {
        telegramSupport = prefs.getString(_cachedTelegramSupportKey) ?? telegramSupport;
      } else {
        final jsonStr = await rootBundle.loadString('assets/version.json');
        final data = jsonDecode(jsonStr);
        if (data['telegram_support'] != null &&
            data['telegram_support'].toString().trim().isNotEmpty) {
          telegramSupport = data['telegram_support'].toString().trim();
          await prefs.setString(_cachedTelegramSupportKey, telegramSupport);
        }
      }
    } catch (_) {}
    return telegramSupport;
  }

  static Future<int> getRewardAdDurationSeconds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_cachedRewardAdDurationKey)) {
        rewardAdDurationSeconds = prefs.getInt(_cachedRewardAdDurationKey) ?? 20;
      } else {
        final jsonStr = await rootBundle.loadString('assets/version.json');
        final data = jsonDecode(jsonStr);
        if (data['reward_ad_duration_seconds'] != null) {
          rewardAdDurationSeconds =
              int.tryParse(data['reward_ad_duration_seconds'].toString()) ?? 20;
          await prefs.setInt(_cachedRewardAdDurationKey, rewardAdDurationSeconds);
        }
      }
    } catch (_) {}
    return rewardAdDurationSeconds;
  }

  static const String _lastFetchKey = 'last_config_fetch_timestamp';
  static const String _backupConfigsKey = 'gist_backup_configs';
  static const Duration _fetchInterval = Duration(hours: 24);
  static const String _repoUpdateUrl =
      'https://raw.githubusercontent.com/mobinsamadir/ivpn_app/main/assets/version.json';
  static const String _cdnUpdateUrl =
      'https://cdn.jsdelivr.net/gh/mobinsamadir/ivpn_app@main/assets/version.json';

  // Mirrors List (GitHub Raw + jsDelivr CDN Mirror)
  static const List<String> _mirrors = [
    'https://raw.githubusercontent.com/mobinsamadir/ivpn-servers/main/real_delay_passed.txt',
    'https://cdn.jsdelivr.net/gh/mobinsamadir/ivpn-servers@main/real_delay_passed.txt',
  ];

  Future<void> checkForUpdates(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      AdvancedLogger.info(
        "[UpdateCheck] Checking for updates... Current Build: $currentBuild",
      );

      String? responseBody;
      try {
        final cacheBuster = DateTime.now().millisecondsSinceEpoch;
        final repoResponse = await http
            .get(Uri.parse('$_repoUpdateUrl?t=$cacheBuster'))
            .timeout(const Duration(seconds: 8));
        if (repoResponse.statusCode == 200) {
          responseBody = repoResponse.body;
        }
      } catch (e) {
        AdvancedLogger.warn("[UpdateCheck] Repo version.json check failed: $e");
      }

      if (responseBody == null) {
        try {
          final cacheBuster = DateTime.now().millisecondsSinceEpoch;
          final response = await http
              .get(Uri.parse('$_cdnUpdateUrl?t=$cacheBuster'))
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            responseBody = response.body;
          }
        } catch (e) {
          AdvancedLogger.warn("[UpdateCheck] CDN Mirror also failed ($e)");
        }
      }

      if (responseBody != null) {
        NetworkTuningConfig.instance.refresh(responseBody);
        final data = await compute(_parseJsonInIsolate, responseBody);
        if (data['telegram_support'] != null &&
            data['telegram_support'].toString().trim().isNotEmpty) {
          telegramSupport = data['telegram_support'].toString().trim();
        }
        final latestBuild =
            int.tryParse(data['version_code']?.toString() ?? '0') ?? 0;
        final version = data['version']?.toString() ?? 'Unknown';
        final notes = data['release_notes']?.toString() ??
            'Bug fixes and performance improvements.';
        var downloadUrl = data['url']?.toString() ?? '';

        if (downloadUrl.isEmpty || downloadUrl.endsWith('/latest')) {
          downloadUrl =
              'https://github.com/mobinsamadir/ivpn_app/releases/latest/download/iVPN-release.apk';
        }

        final isNewerByVersion = _isVersionNewer(version, info.version);
        final isSameVersion = version == info.version;
        final isNewerByBuild = isSameVersion && (latestBuild > currentBuild);
        final updateAvailable = isNewerByVersion || isNewerByBuild;

        AdvancedLogger.info(
            "[UpdateCheck] Local: ${info.version}+$currentBuild | Remote: $version+$latestBuild | Update Available: $updateAvailable");

        if (updateAvailable && downloadUrl.isNotEmpty) {
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => UpdateDialog(
                version: version,
                releaseNotes: notes,
                downloadUrl: downloadUrl,
              ),
            );
          }
        }
      }
    } catch (e) {
      AdvancedLogger.warn("[UpdateCheck] Failed: $e");
    }
  }

  static bool _isVersionNewer(String remote, String local) {
    try {
      final rParts =
          remote.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final lParts =
          local.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      for (int i = 0; i < 3; i++) {
        final r = i < rParts.length ? rParts[i] : 0;
        final l = i < lParts.length ? lParts[i] : 0;
        if (r > l) return true;
        if (r < l) return false;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> fetchAndApplyConfigs(
    ConfigManager manager, {
    bool force = false,
  }) async {
    try {
    final prefs = await SharedPreferences.getInstance();
    final lastFetchTs = prefs.getInt(_lastFetchKey) ?? 0;
    final lastFetch = DateTime.fromMillisecondsSinceEpoch(lastFetchTs);
    final now = DateTime.now();

    // Smart Logic: Fetch if FORCED OR (Empty List) OR (Time > 24h)
    if (!force &&
        manager.allConfigs.isNotEmpty &&
        now.difference(lastFetch) < _fetchInterval) {
      AdvancedLogger.info(
        "[ConfigGistService] Skipping fetch. Last fetch: $lastFetch",
      );
      return true; // Consider success as we have configs
    }

    AdvancedLogger.info(
      "[ConfigGistService] Starting fetch (Force: $force)...",
    );

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
                return c.replaceAll(_spiderXRegex, '');
              }).toList();

              // Add to Manager
              final added = await manager.addConfigs(
                cleaned,
                checkBlacklist: true,
              );
              if (added > 0) {
                AdvancedLogger.info(
                  "[ConfigGistService] Added $added configs from $url",
                );
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
      AdvancedLogger.info(
        "[ConfigGistService] Fetch complete. Timestamp updated.",
      );
      return true;
    } else {
      AdvancedLogger.error("[ConfigGistService] All mirrors failed.");

      // Fail-safe
      final backupJson = prefs.getString(_backupConfigsKey);
      if (backupJson != null && backupJson.isNotEmpty) {
        try {
          final List<dynamic> rawList =
              await compute(_parseJson, backupJson) as List<dynamic>;
          final List<String> backupConfigs = [];
          for (var e in rawList) {
            String c = e.toString();
            if (c.trim().isEmpty) continue;
            if (!c.trim().startsWith('{')) {
              // If it doesn't start with {, it's likely a raw URL, which addConfigs handles
              // If it's supposed to be JSON, this would be an issue. But addConfigs parses URLs.
              backupConfigs.add(c);
              continue;
            }
            try {
              jsonDecode(c);
              backupConfigs.add(c);
            } catch (_) {}
          }

          if (backupConfigs.isNotEmpty) {
            AdvancedLogger.warn(
              "⚠️ Network failure. Using last known good configuration.",
            );
            final added = await manager.addConfigs(
              backupConfigs,
              checkBlacklist: true,
            );
            AdvancedLogger.info(
              "[ConfigGistService] Restored $added configs from backup.",
            );
            return true; // Success via backup
          }
        } catch (e) {
          AdvancedLogger.error("APP_ERROR: Failed to load backup: $e");
        }
      }
      return false; // Total failure
    }
    } on TimeoutException catch (e, stackTrace) {
      AdvancedLogger.error("[ConfigGistService] Timeout in fetchAndApplyConfigs: $e\n$stackTrace");
      return false;
    } on SocketException catch (e, stackTrace) {
      AdvancedLogger.error("[ConfigGistService] Network error in fetchAndApplyConfigs: $e\n$stackTrace");
      return false;
    } catch (e, stackTrace) {
      AdvancedLogger.error("[ConfigGistService] Unhandled exception in fetchAndApplyConfigs: $e\n$stackTrace");
      return false;
    }
  }

  Future<String?> _robustFetch(String url) async {
    String targetUrl = url;

    // 1. Auto-convert Google Drive /view links
    if (targetUrl.contains('drive.google.com') && targetUrl.contains('/view')) {
      final fileIdMatch = RegExp(
        r'\/d\/([a-zA-Z0-9_-]+)',
      ).firstMatch(targetUrl);
      if (fileIdMatch != null) {
        final fileId = fileIdMatch.group(1);
        targetUrl = 'https://drive.google.com/uc?export=download&id=$fileId';
      }
    }

    try {
      final response = await http.get(
        Uri.parse(targetUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 15)); // strict 15-second timeout

      if (response.statusCode != 200) return null;

      String content = response.body;

      // 2. Google Drive Warning Check
      if (targetUrl.contains('drive.google.com') &&
          (content.contains('confirm=') ||
              content.contains('Virus scan warning'))) {
        final confirmToken = _extractDriveToken(content);
        if (confirmToken != null) {
          final fileIdMatch = RegExp(
            r'id=([a-zA-Z0-9_-]+)',
          ).firstMatch(targetUrl);
          final fileId = fileIdMatch?.group(1);
          if (fileId != null) {
            final confirmUrl =
                'https://drive.google.com/uc?export=download&id=$fileId&confirm=$confirmToken';
            final retryResponse = await http.get(Uri.parse(confirmUrl));
            if (retryResponse.statusCode == 200) content = retryResponse.body;
          }
        }
      }

      return content;
    } on TimeoutException catch (e) {
      AdvancedLogger.warn("Timeout fetching from $url: $e");
      return null;
    } on SocketException catch (e) {
      AdvancedLogger.warn("SocketException (Network Error) fetching from $url: $e");
      return null;
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
        if (uri.queryParameters.containsKey('confirm')) {
          return uri.queryParameters['confirm'];
        }
      }
    } catch (_) {}
    return null;
  }
}

// Top-level function for background isolate JSON decoding
dynamic _parseJsonInIsolate(String jsonStr) => jsonDecode(jsonStr);
