
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/advanced_logger.dart';
import '../utils/file_logger.dart';
import 'singbox_config_generator.dart';

// Top-level function for compute to prevent UI lag
String _generateConfigWrapper(Map<String, dynamic> args) {
  return SingboxConfigGenerator.generateConfig(
    args['configContent'],
    listenPort: args['listenPort'],
    isTest: args['isTest'],
  );
}

class WindowsVpnService {
  static bool isUserInitiatedDisconnect = false;
  Process? _process;
  
  // Log Stream (Stdout/Stderr)
  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  // Status Stream (CONNECTED, DISCONNECTED, etc. for HomeProvider)
  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  static Future<String> getExecutablePath() async {
    // Check in the current directory
    final localPath = p.join(Directory.current.path, 'assets', 'executables', 'windows', 'sing-box.exe');
    debugPrint('Checking for Sing-box at local path: $localPath');
    if (File(localPath).existsSync()) {
      debugPrint('Found Sing-box at local path: $localPath');
      return localPath;
    }

    // Check in the app's installation directory (for release builds)
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final bundledPath = p.join(exeDir, 'data', 'flutter_assets', 'assets', 'executables', 'windows', 'sing-box.exe');
    debugPrint('Checking for Sing-box at bundled path: $bundledPath');
    if (File(bundledPath).existsSync()) {
      debugPrint('Found Sing-box at bundled path: $bundledPath');
      return bundledPath;
    }

    // Check in the parent directory of the executable (alternative location for release builds)
    final altPath = p.join(exeDir, 'assets', 'executables', 'windows', 'sing-box.exe');
    debugPrint('Checking for Sing-box at alternative path: $altPath');
    if (File(altPath).existsSync()) {
      debugPrint('Found Sing-box at alternative path: $altPath');
      return altPath;
    }

    // Check in the Resources directory (common for packaged apps)
    final resourcesPath = p.join(exeDir, 'Resources', 'assets', 'executables', 'windows', 'sing-box.exe');
    debugPrint('Checking for Sing-box at resources path: $resourcesPath');
    if (File(resourcesPath).existsSync()) {
      debugPrint('Found Sing-box at resources path: $resourcesPath');
      return resourcesPath;
    }

    // CRITICAL: Add a fallback check for development mode
    final projectRootPath = p.join(Directory.current.path, 'assets', 'executables', 'windows', 'sing-box.exe');
    debugPrint('Checking for Sing-box at project root path (development): $projectRootPath');
    if (File(projectRootPath).existsSync()) {
      debugPrint('Found Sing-box at project root path: $projectRootPath');
      return projectRootPath;
    }

    throw Exception("Sing-box executable not found. Checked:\n- $localPath\n- $bundledPath\n- $altPath\n- $resourcesPath\n- $projectRootPath");
  }

  static Future<String> getGeoIpPath() async {
    // Check in the current directory
    final localPath = p.join(Directory.current.path, 'assets', 'executables', 'windows', 'geoip.db');
    debugPrint('Checking for geoip.db at local path: $localPath');
    if (File(localPath).existsSync()) {
      debugPrint('Found geoip.db at local path: $localPath');
      return localPath;
    }

    // Check in the app's installation directory (for release builds)
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final bundledPath = p.join(exeDir, 'data', 'flutter_assets', 'assets', 'executables', 'windows', 'geoip.db');
    debugPrint('Checking for geoip.db at bundled path: $bundledPath');
    if (File(bundledPath).existsSync()) {
      debugPrint('Found geoip.db at bundled path: $bundledPath');
      return bundledPath;
    }

    // Check in the parent directory of the executable (alternative location for release builds)
    final altPath = p.join(exeDir, 'assets', 'executables', 'windows', 'geoip.db');
    debugPrint('Checking for geoip.db at alternative path: $altPath');
    if (File(altPath).existsSync()) {
      debugPrint('Found geoip.db at alternative path: $altPath');
      return altPath;
    }

    // Check in the Resources directory (common for packaged apps)
    final resourcesPath = p.join(exeDir, 'Resources', 'assets', 'executables', 'windows', 'geoip.db');
    debugPrint('Checking for geoip.db at resources path: $resourcesPath');
    if (File(resourcesPath).existsSync()) {
      debugPrint('Found geoip.db at resources path: $resourcesPath');
      return resourcesPath;
    }

    throw Exception("geoip.db not found. Checked:\n- $localPath\n- $bundledPath\n- $altPath\n- $resourcesPath");
  }

  static Future<String> getGeoSitePath() async {
    // Check in the current directory
    final localPath = p.join(Directory.current.path, 'assets', 'executables', 'windows', 'geosite.db');
    debugPrint('Checking for geosite.db at local path: $localPath');
    if (File(localPath).existsSync()) {
      debugPrint('Found geosite.db at local path: $localPath');
      return localPath;
    }

    // Check in the app's installation directory (for release builds)
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final bundledPath = p.join(exeDir, 'data', 'flutter_assets', 'assets', 'executables', 'windows', 'geosite.db');
    debugPrint('Checking for geosite.db at bundled path: $bundledPath');
    if (File(bundledPath).existsSync()) {
      debugPrint('Found geosite.db at bundled path: $bundledPath');
      return bundledPath;
    }

    // Check in the parent directory of the executable (alternative location for release builds)
    final altPath = p.join(exeDir, 'assets', 'executables', 'windows', 'geosite.db');
    debugPrint('Checking for geosite.db at alternative path: $altPath');
    if (File(altPath).existsSync()) {
      debugPrint('Found geosite.db at alternative path: $altPath');
      return altPath;
    }

    // Check in the Resources directory (common for packaged apps)
    final resourcesPath = p.join(exeDir, 'Resources', 'assets', 'executables', 'windows', 'geosite.db');
    debugPrint('Checking for geosite.db at resources path: $resourcesPath');
    if (File(resourcesPath).existsSync()) {
      debugPrint('Found geosite.db at resources path: $resourcesPath');
      return resourcesPath;
    }

    throw Exception("geosite.db not found. Checked:\n- $localPath\n- $bundledPath\n- $altPath\n- $resourcesPath");
  }

  Future<bool> checkRequiredAssets() async {
    try {
      await WindowsVpnService.getExecutablePath();
      await WindowsVpnService.getGeoIpPath();
      await WindowsVpnService.getGeoSitePath();
      return true;
    } catch (e) {
      debugPrint('Missing required assets: $e');
      return false;
    }
  }

  Future<bool> isAdmin() async {
    try {
      final result = await Process.run('fsutil', ['dirty', 'query', 'C:']);
      final isAdmin = result.exitCode == 0;
      AdvancedLogger.info('[WindowsVpnService] isAdmin check result: $isAdmin');
      return isAdmin;
    } catch (e) {
      AdvancedLogger.error('[WindowsVpnService] isAdmin check failed: $e');
      return false;
    }
  }



  Future<void> startVpn(String configContent) async {
    isUserInitiatedDisconnect = false;
    AdvancedLogger.info('[WindowsVpnService] startVpn called with config length: ${configContent.length}');

    // 1. Ensure clean slate - Force kill any existing sing-box processes to free up ports
    await _forceKillSingBoxProcesses();
    AdvancedLogger.info('[WindowsVpnService] Previous VPN connection stopped and processes cleaned up');

    if (Platform.isWindows && !await isAdmin()) {
      _logController.add("❌ ERROR: TUN mode requires Administrator privileges.");
      _statusController.add("ERROR");
      AdvancedLogger.error('[WindowsVpnService] Administrator privileges required');
      throw Exception("Administrator privileges required. Please run the application as Administrator.");
    }

    // Check for required assets before starting
    if (!await checkRequiredAssets()) {
      _logController.add("❌ ERROR: Required assets (geoip.db, geosite.db) are missing.");
      _statusController.add("ERROR");
      AdvancedLogger.error('[WindowsVpnService] Required assets are missing');
      throw Exception("Required assets are missing. Please ensure geoip.db and geosite.db are included in the build.");
    }

    try {
      _statusController.add("CONNECTING");
      AdvancedLogger.info('[WindowsVpnService] Setting status to CONNECTING');

      final exePath = await WindowsVpnService.getExecutablePath();
      debugPrint('Attempting to run Sing-box at path: $exePath');
      AdvancedLogger.info('[WindowsVpnService] Sing-box executable path: $exePath');

      final geoIpPath = await WindowsVpnService.getGeoIpPath();
      AdvancedLogger.info('[WindowsVpnService] GeoIP database path: $geoIpPath');

      final geoSitePath = await WindowsVpnService.getGeoSitePath();
      AdvancedLogger.info('[WindowsVpnService] GeoSite database path: $geoSitePath');

      final workingDir = p.dirname(exePath);
      final binDir = p.dirname(exePath);
      AdvancedLogger.info('[WindowsVpnService] Working directory: $workingDir, Bin directory: $binDir');

      // Copy database files to the same directory as sing-box.exe if they're not already there
      await _ensureDatabaseFiles(binDir, geoIpPath, geoSitePath);
      AdvancedLogger.info('[WindowsVpnService] Database files ensured in bin directory');

      // If the input is not JSON (it's a raw link), convert it first.
      String jsonConfig;
      if (configContent.trim().startsWith("{")) {
          jsonConfig = configContent;
          AdvancedLogger.info('[WindowsVpnService] Config is already JSON format');
      } else {
          AdvancedLogger.info('[WindowsVpnService] Converting config from raw format to JSON (in background isolate)');
          // Generate PRODUCTION config (isTest: false) in background isolate
          jsonConfig = await compute(_generateConfigWrapper, {
            'configContent': configContent,
            'listenPort': 2080, // Main port for production
            'isTest': false,    // <--- CRITICAL: Enables TUN and Secure DNS
          });
          AdvancedLogger.info('[WindowsVpnService] Generated JSON config length: ${jsonConfig.length}');
      }

      final tempDir = await getTemporaryDirectory();
      final configFile = File(p.join(tempDir.path, 'config.json'));
      await configFile.writeAsString(jsonConfig);
      AdvancedLogger.info('[WindowsVpnService] Config file written to: ${configFile.path}');

      _logController.add("🚀 Starting Sing-box Core...");
      _logController.add("📂 Executable: $exePath");
      _logController.add("📂 Config: ${configFile.path}");
      _logController.add("📂 Database files: geoip.db, geosite.db");
      AdvancedLogger.info('[WindowsVpnService] Starting Sing-box process with args: [run, -c, ${configFile.path}, -D, $binDir]');

      // Add extra validation before starting the process
      final exeFile = File(exePath);
      if (!await exeFile.exists()) {
        throw Exception("Sing-box executable does not exist at path: $exePath");
      }

      if (!await configFile.exists()) {
        throw Exception("Configuration file does not exist at path: ${configFile.path}");
      }

      // Print the EXACT command and path being run using AdvancedLogger
      final commandArgs = ['run', '-c', configFile.path, '-D', binDir];
      AdvancedLogger.info('[WindowsVpnService] Executing command: $exePath ${commandArgs.join(' ')}');
      AdvancedLogger.info('[WindowsVpnService] Working directory: $binDir');
      AdvancedLogger.info('[WindowsVpnService] Environment: {ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS: true}');

      // Log the generated config content to verify it's valid
      try {
        final configContent = await File(configFile.path).readAsString();
        AdvancedLogger.info('--- GENERATED SING-BOX CONFIG ---');
        AdvancedLogger.info(configContent);
        AdvancedLogger.info('---------------------------------');
      } catch (e) {
        AdvancedLogger.error('Failed to read generated config for logging: $e');
      }

      AdvancedLogger.info('[WindowsVpnService] Starting Sing-box in: $binDir');
      _process = await Process.start(
        exePath,
        ['run', '-c', configFile.path], // REMOVED: '-D', binDir
        workingDirectory: binDir, // This is enough and handles spaces correctly
        runInShell: false, // Set to false to avoid CMD parsing issues with spaces
        environment: {
          'ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS': 'true',
        },
      );
      AdvancedLogger.info('[WindowsVpnService] Process started successfully, PID: ${_process?.pid}');

      // Listen to process.stdout and process.stderr immediately to capture why it fails to start
      _process!.stdout.transform(utf8.decoder).listen((data) {
        final trimmedData = data.trim();
        if (trimmedData.isNotEmpty) {
          _logController.add(trimmedData);
          AdvancedLogger.info('[WindowsVpnService] stdout: $trimmedData');
        }
      });

      _process!.stderr.transform(utf8.decoder).listen((data) {
        final trimmedData = data.trim();
        if (trimmedData.isNotEmpty) {
          // Sing-box logs mostly to stderr
          _logController.add(trimmedData);
          // Log as error if it looks like an error message, otherwise as info
          if (trimmedData.toLowerCase().contains('error') ||
              trimmedData.toLowerCase().contains('exception') ||
              trimmedData.toLowerCase().contains('failed') ||
              trimmedData.toLowerCase().contains('fatal')) {
            AdvancedLogger.error('[WindowsVpnService] stderr: $trimmedData');
          } else {
            AdvancedLogger.info('[WindowsVpnService] stderr: $trimmedData');
          }

          if (trimmedData.toLowerCase().contains("started") || trimmedData.toLowerCase().contains("tun")) {
             _statusController.add("CONNECTED");
             _logController.add("✅ VPN Connection Established Successfully");
             AdvancedLogger.info('[WindowsVpnService] VPN connection established successfully');
          }
        }
      });

      _process!.exitCode.then((code) {
         _logController.add("🛑 Sing-box exited with code: $code");
         AdvancedLogger.info('[WindowsVpnService] Sing-box process exited with code: $code');
         // Always update status when process exits, regardless of whether it was manually stopped
         _statusController.add("DISCONNECTED");
         _process = null;
      });

      // Wait a bit to ensure the process started successfully
      await Future.delayed(const Duration(seconds: 2));
      AdvancedLogger.info('[WindowsVpnService] Waiting completed, checking process status');

      // Double-check that the process is still running
      if (_process != null) {
        _statusController.add("CONNECTED");
        _logController.add("✅ VPN Connection Confirmed Stable");
        AdvancedLogger.info('[WindowsVpnService] VPN connection confirmed stable');
      } else {
        _statusController.add("ERROR");
        _logController.add("❌ VPN Process Failed to Start Properly");
        AdvancedLogger.error('[WindowsVpnService] VPN process failed to start properly');
        throw Exception("VPN process failed to start properly");
      }

    } catch (e, stackTrace) {
      _logController.add("❌ Connection Failed: $e");
      _statusController.add("ERROR");
      AdvancedLogger.error('[WindowsVpnService] Connection failed with error: $e', error: e, stackTrace: stackTrace);
      FileLogger.log("Connection Error: $e");
      rethrow;
    }
  }

  // Helper method to ensure database files are in the same directory as sing-box.exe
  Future<void> _ensureDatabaseFiles(String binDir, String geoIpPath, String geoSitePath) async {
    final targetGeoIpPath = p.join(binDir, 'geoip.db');
    final targetGeoSitePath = p.join(binDir, 'geosite.db');

    // Copy geoip.db if it doesn't exist in the target directory
    if (!File(targetGeoIpPath).existsSync()) {
      await File(geoIpPath).copy(targetGeoIpPath);
      _logController.add("📋 Copied geoip.db to executable directory");
    }

    // Copy geosite.db if it doesn't exist in the target directory
    if (!File(targetGeoSitePath).existsSync()) {
      await File(geoSitePath).copy(targetGeoSitePath);
      _logController.add("📋 Copied geosite.db to executable directory");
    }
  }

  // Helper method to force kill sing-box processes
  Future<void> _forceKillSingBoxProcesses() async {
    try {
      if (Platform.isWindows) {
        // Force kill any existing sing-box processes to free up ports immediately
        final result = await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']);
        if (result.stderr.toString().isEmpty || !result.stderr.toString().contains('not found')) {
          AdvancedLogger.info('Forcefully killed any lingering sing-box processes. Result: ${result.stdout}');
        } else {
          AdvancedLogger.info('No sing-box.exe processes found to kill');
        }
      }
    } catch (e) {
      AdvancedLogger.warn('Error during force kill of sing-box processes: $e');
      // Continue even if there's an error
    }
  }

  Future<void> stopVpn() async {
    isUserInitiatedDisconnect = true;
    AdvancedLogger.info('[WindowsVpnService] stopVpn called');
    _logController.add("🔻 Stopping VPN...");

    // Force kill any existing sing-box processes to free up ports immediately
    try {
      if (Platform.isWindows) {
        // Force kill any existing sing-box processes to free up ports immediately
        await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']);
        AdvancedLogger.info('Forcefully killed any lingering sing-box processes.');
      }
    } catch (e) {
      // Ignore errors if process wasn't found
    }

    if (_process != null) {
      try {
        AdvancedLogger.info('[WindowsVpnService] Killing VPN process with PID: ${_process!.pid}');
        // Try graceful shutdown first
        _process!.kill(ProcessSignal.sigterm);
        // Wait a moment for graceful shutdown
        await Future.delayed(const Duration(milliseconds: 500));

        // Check if process is still running
        if (_process != null) {
          // Force kill if still running
          AdvancedLogger.info('[WindowsVpnService] Force killing VPN process with PID: ${_process!.pid}');
          _process!.kill(ProcessSignal.sigkill);
        }
        _process = null;
        AdvancedLogger.info('[WindowsVpnService] VPN process killed successfully');
      } catch (e, stackTrace) {
        AdvancedLogger.error('[WindowsVpnService] Error during VPN stop: $e', error: e, stackTrace: stackTrace);
        _logController.add("Warning during VPN stop: $e");
      }
    } else {
      AdvancedLogger.info('[WindowsVpnService] No VPN process to stop');
    }

    // Heavy-Duty Disconnect: Kill all sing-box processes including child processes
    try {
      AdvancedLogger.info('[WindowsVpnService] Killing all sing-box.exe processes');
      final result = await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe', '/T']);
      // Only log if the command was successful and actually killed processes
      if (result.stderr.toString().isEmpty || !result.stderr.toString().contains('not found')) {
        _logController.add("Force killed all sing-box.exe processes and child processes");
        AdvancedLogger.info('[WindowsVpnService] Killed all sing-box.exe processes. Stdout: ${result.stdout}, Stderr: ${result.stderr}');
      } else {
        AdvancedLogger.info('[WindowsVpnService] No sing-box.exe processes found to kill');
      }
    } catch (e, stackTrace) {
      // Silently ignore if process doesn't exist, only log for other errors
      AdvancedLogger.error('[WindowsVpnService] Error during heavy-duty cleanup: $e', error: e, stackTrace: stackTrace);
      if (e.toString().toLowerCase().contains('error') && !e.toString().toLowerCase().contains('not found')) {
        _logController.add("Error during heavy-duty cleanup: $e");
      }
    }

    _statusController.add("DISCONNECTED");
    AdvancedLogger.info('[WindowsVpnService] VPN stopped, status set to DISCONNECTED');
  }
}
