import 'dart:async';
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
    // Use addPostFrameCallback to ensure build context is ready if needed,
    // though initState is safe for starting async work.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _initialize() async {
    if (!mounted) return;

    setState(() {
      _errorMessage = null;
    });

    try {
      // 1. Initialize Loggers (Critical for debugging, idempotent)
      // We wrap this in a try-catch and timeout because if logging fails,
      // the app should still try to run.
      try {
        await AdvancedLogger.init().timeout(const Duration(seconds: 2));
        await FileLogger.init().timeout(const Duration(seconds: 2));
        AdvancedLogger.info('🚀 [Splash] Initialization started');
      } catch (e) {
        debugPrint("Logger initialization failed or timed out: $e");
        // Continue anyway
      }

      // 2. Asset Check (Critical for VPN functionality)
      // On Windows, we verify sing-box.exe and databases are accessible.
      if (Platform.isWindows) {
        AdvancedLogger.info('[Splash] Checking required assets...');
        final windowsService = WindowsVpnService();

        bool assetsExist = false;
        try {
           assetsExist = await windowsService.checkRequiredAssets().timeout(
             const Duration(seconds: 5),
             onTimeout: () {
               AdvancedLogger.warn('[Splash] Asset check timed out');
               throw TimeoutException('Asset check timed out');
             }
           );
        } catch (e) {
           AdvancedLogger.error('[Splash] Asset check failed', error: e);
           // If asset check fails, we might still want to let the user in,
           // but they won't be able to connect.
           // Better to show error here.
           rethrow;
        }

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
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('SharedPreferences init timed out'),
      );
      final storageService = StorageService(prefs: prefs);

      // Initialize ConfigManager with local data first (fast)
      // fetchRemote: false prevents blocking on network
      await ConfigManager().init(fetchRemote: false).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AdvancedLogger.warn('[Splash] ConfigManager init timed out, skipping');
        }
      );

      // 4. Trigger Background Fetch (Non-blocking)
      // We don't await this; it updates the ConfigManager state asynchronously.
      // ConnectionHomeScreen will react to changes via Listeners.
      ConfigManager().fetchStartupConfigs().catchError((e) {
        AdvancedLogger.warn('[Splash] Background config fetch warning: $e');
      });

      // 5. Complete Initialization
      AdvancedLogger.info('[Splash] Initialization complete, navigating to Home');

      // Artificial delay to prevent flicker if everything was too fast?
      // No, fast is good.

      if (mounted) {
        widget.onInitializationComplete(storageService);
      }
    } catch (e, stackTrace) {
      debugPrint("SPLASH INITIALIZATION ERROR: $e");
      try {
        AdvancedLogger.error('[Splash] Initialization failed', error: e, stackTrace: stackTrace);
      } catch (_) {}

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
