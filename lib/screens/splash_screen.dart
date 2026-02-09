import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/advanced_logger.dart'; // Corrected import
import '../services/file_logger.dart';
import '../services/storage_service.dart';
import '../services/config_manager.dart';
import '../services/windows_vpn_service.dart';

class SplashScreen extends StatefulWidget {
  final Function(StorageService) onInitializationComplete;

  const SplashScreen({super.key, required this.onInitializationComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (!mounted) return;

    setState(() {
      _errorMessage = null;
    });

    try {
      // 1. Initialize Loggers (Critical for debugging, idempotent)
      // We do this first so any subsequent errors are logged properly.
      await AdvancedLogger.init();
      await FileLogger.init();
      AdvancedLogger.info('🚀 [Splash] Initialization started');

      // 2. Asset Check (Critical for VPN functionality)
      // On Windows, we verify sing-box.exe and databases are accessible.
      if (Platform.isWindows) {
        AdvancedLogger.info('[Splash] Checking required assets...');
        final windowsService = WindowsVpnService();
        final assetsExist = await windowsService.checkRequiredAssets();

        if (!assetsExist) {
          throw Exception(
            "Critical assets missing.\n"
            "Please ensure sing-box.exe and geoip.db/geosite.db are in the correct location."
          );
        }
        AdvancedLogger.info('[Splash] Assets verified successfully');
      }

      // 3. Initialize Storage & ConfigManager
      AdvancedLogger.info('[Splash] Loading preferences & configs...');
      final prefs = await SharedPreferences.getInstance();
      final storageService = StorageService(prefs: prefs);

      // Initialize ConfigManager with local data first (fast)
      // fetchRemote: false prevents blocking on network
      await ConfigManager().init(fetchRemote: false);

      // 4. Trigger Background Fetch (Non-blocking)
      // We don't await this; it updates the ConfigManager state asynchronously.
      // ConnectionHomeScreen will react to changes via Listeners.
      ConfigManager().fetchStartupConfigs().catchError((e) {
        AdvancedLogger.warn('[Splash] Background config fetch warning: $e');
      });

      // 5. Complete Initialization
      AdvancedLogger.info('[Splash] Initialization complete, navigating to Home');
      if (mounted) {
        widget.onInitializationComplete(storageService);
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error('[Splash] Initialization failed', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo or App Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1E1E1E),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.vpn_lock,
                  size: 60,
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 40),

              // Status / Error UI
              if (_errorMessage != null) ...[
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  "Initialization Failed",
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _initialize,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Retry"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ] else ...[
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Preparing secure connection...",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
