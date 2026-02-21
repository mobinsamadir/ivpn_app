import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileLogger {
  static File? _logFile;

  static Future<void> init() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File(p.join(directory.path, 'vpn_debug.log'));

      // Clear log on startup or keep it?
      // User likely wants to see the latest attempt, so we append with a separator.
      await log("------------------------------------------");
      await log("Session Started: ${DateTime.now()}");
    } catch (e) {
      print("Error initializing FileLogger: $e");
    }
  }

  static Future<void> log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final formattedLine = "[$timestamp] $message\n";

    // Also print to console for development
    print(formattedLine.trim());

    if (_logFile != null) {
      try {
        await _logFile!.writeAsString(formattedLine, mode: FileMode.append);
      } catch (e) {
        print("Failed to write to log file: $e");
      }
    }
  }

  static Future<String> getLogPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, 'vpn_debug.log');
  }
}
