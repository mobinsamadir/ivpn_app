import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/config_manager.dart';
import '../utils/advanced_logger.dart';
import '../services/ad_manager_service.dart';
import '../services/funnel_service.dart';
import 'connection_home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusMessage = 'Initializing...';
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Run after first frame render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    setState(() {
      _hasError = false;
      _statusMessage = 'Initializing services...';
    });

    try {
      // 1. Get Global Config Manager (Injected in main.dart)
      final configManager = context.read<ConfigManager>();

      // 0. Request Notification Permission (Android 13+)
      await Permission.notification.request();
      
      // 2. Initialize Config Logic
      setState(() => _statusMessage = 'Loading configs...');
      // Robust init with timeout to prevent hang
      await configManager.init().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AdvancedLogger.error("ConfigManager.init timed out!");
          // Don't throw, just proceed. Some configs might be missing but app won't hang.
        }
      );

      // NEW: Start Funnel immediately
      FunnelService().startFunnel();

      // NEW: Initialize Ads
      AdManagerService().initialize();

      // 3. Fetch Updates (Now handled by ConnectionHomeScreen logic or ConfigGistService)
      // Removed direct call to fetchStartupConfigs as it was migrated.

      // 4. Navigate to Home
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ConnectionHomeScreen()),
        );
      }
    } catch (e, stack) {
      AdvancedLogger.error("Splash Init Error", error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _hasError = true;
          _statusMessage = '';
          _errorMessage = 'Initialization Failed:\n$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[900], // Dark theme background
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              const Icon(Icons.vpn_lock, size: 80, color: Colors.white),
              const SizedBox(height: 24),
              
              // Status or Error
              if (_hasError) ...[
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Unknown Error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _initializeApp,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                )
              ] else ...[
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 24),
                Text(
                  _statusMessage,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
