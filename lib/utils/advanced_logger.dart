import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:developer' as developer;

enum LogLevel { DEBUG, INFO, WARN, ERROR }

/// Advanced logging system with multi-level logging, file persistence, and network tracing
class AdvancedLogger {
  static File? _logFile;
  static final List<String> _buffer = [];
  static const int _bufferSize = 50; // Flush every 50 entries
  static LogLevel _minLevel = LogLevel.DEBUG;

  // Memory buffering for in-app viewing
  static final List<String> _logHistory = [];
  static final ValueNotifier<List<String>> logNotifier = ValueNotifier([]);
  static const int _maxLogEntries = 1000; // Keep last 1000 log entries

  /// Initialize the logger
  static Future<void> init({LogLevel minLevel = LogLevel.DEBUG}) async {
    _minLevel = minLevel;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      _logFile = File(p.join(directory.path, 'vpn_log_$timestamp.jsonl'));

      // Write initial marker
      await _writeEntry({
        'level': 'INFO',
        'timestamp': DateTime.now().toIso8601String(),
        'message': '=== NEW SESSION STARTED ===',
        'metadata': {
          'platform': Platform.operatingSystem,
          'version': Platform.operatingSystemVersion,
        }
      });

      print('✅ AdvancedLogger initialized: ${_logFile!.path}');
    } catch (e) {
      print('❌ Failed to initialize AdvancedLogger: $e');
    }
  }

  /// Debug level logging
  static void debug(String message, {Map<String, dynamic>? metadata}) {
    _log(LogLevel.DEBUG, message, metadata: metadata);
  }

  /// Info level logging
  static void info(String message, {Map<String, dynamic>? metadata}) {
    _log(LogLevel.INFO, message, metadata: metadata);
  }

  /// Warning level logging
  static void warn(String message, {Map<String, dynamic>? metadata}) {
    _log(LogLevel.WARN, message, metadata: metadata);
  }

  /// Error level logging
  static void error(String message, {dynamic error, StackTrace? stackTrace, Map<String, dynamic>? metadata}) {
    final combinedMetadata = metadata ?? {};
    if (error != null) combinedMetadata['error'] = error.toString();
    if (stackTrace != null) combinedMetadata['stackTrace'] = stackTrace.toString();
    _log(LogLevel.ERROR, message, metadata: combinedMetadata);
  }

  /// Network request logging
  static void networkRequest(String method, String url, {Map<String, dynamic>? headers, dynamic body}) {
    _log(LogLevel.INFO, 'HTTP $method $url', metadata: {
      'type': 'network_request',
      'method': method,
      'url': url,
      'headers': headers,
      'body': body,
    });
  }

  /// Network response logging
  static void networkResponse(String url, int statusCode, {dynamic body, Duration? duration}) {
    _log(LogLevel.INFO, 'HTTP Response [$statusCode] $url', metadata: {
      'type': 'network_response',
      'url': url,
      'statusCode': statusCode,
      'body': body,
      'durationMs': duration?.inMilliseconds,
    });
  }

  /// Get the current log file path
  static Future<String> getLogPath() async {
    if (_logFile != null) return _logFile!.path;
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, 'vpn_logs');
  }

  /// Private logging method
  static void _log(LogLevel level, String message, {Map<String, dynamic>? metadata}) {
    if (level.index < _minLevel.index) return;

    final entry = {
      'level': level.toString().split('.').last,
      'timestamp': DateTime.now().toIso8601String(),
      'message': message,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    };

    // Console output with colors
    final color = _getColorCode(level);
    const reset = '\x1B[0m';
    final levelStr = level.toString().split('.').last.padRight(5);
    print('$color[$levelStr]$reset $message');
    if (metadata != null && metadata.isNotEmpty) {
      print('  └─ ${jsonEncode(metadata)}');
    }

    // Format log for in-app viewer: [TIME] [LEVEL] Message
    final formattedLog = '[${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}] [${level.toString().split('.').last}] $message';

    // Add to memory buffer
    _logHistory.add(formattedLog);

    // Maintain max log entries
    if (_logHistory.length > _maxLogEntries) {
      _logHistory.removeAt(0); // Remove oldest entry
    }

    // Update notifier for UI
    logNotifier.value = List.from(_logHistory);
    logNotifier.notifyListeners();

    // Add to file buffer
    _buffer.add(jsonEncode(entry));

    // Flush if buffer is full
    if (_buffer.length >= _bufferSize) {
      _flush();
    }
  }

  /// Write entry to file
  static Future<void> _writeEntry(Map<String, dynamic> entry) async {
    if (_logFile == null) return;
    try {
      await _logFile!.writeAsString(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      print('Failed to write log entry: $e');
    }
  }

  /// Flush buffer to file
  static Future<void> _flush() async {
    if (_logFile == null || _buffer.isEmpty) return;
    try {
      final content = '${_buffer.join('\n')}\n';
      await _logFile!.writeAsString(content, mode: FileMode.append);
      _buffer.clear();
    } catch (e) {
      print('Failed to flush log buffer: $e');
    }
  }

  /// Force flush (call before app exit)
  static Future<void> close() async {
    await _flush();
    info('=== SESSION ENDED ===');
    await _flush(); // Flush the end marker too
  }

  /// Get console color code for log level
  static String _getColorCode(LogLevel level) {
    switch (level) {
      case LogLevel.DEBUG:
        return '\x1B[36m'; // Cyan
      case LogLevel.INFO:
        return '\x1B[32m'; // Green
      case LogLevel.WARN:
        return '\x1B[33m'; // Yellow
      case LogLevel.ERROR:
        return '\x1B[31m'; // Red
    }
  }
}