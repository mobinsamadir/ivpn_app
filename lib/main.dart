import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'utils/advanced_logger.dart';
import 'services/file_logger.dart';
import 'services/storage_service.dart';
import 'services/config_manager.dart';
import 'utils/cleanup_utils.dart';
import 'providers/theme_provider.dart';
import 'providers/home_provider.dart';
import 'screens/connection_home_screen.dart';
import 'services/background_ad_service.dart';
import 'screens/splash_screen.dart'; // Ensure this import exists
import 'services/windows_vpn_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.ensureInitialized();
    }

    // Initialize Loggers
    await AdvancedLogger.init();
    AdvancedLogger.info('🚀 IVPN App Initialized', metadata: {
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
    });
    
    await FileLogger.init();
    FileLogger.log("Application starting...");

    // Setup Global Crash Recovery
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AdvancedLogger.error("GLOBAL FLUTTER ERROR", error: details.exception, stackTrace: details.stack);
      CleanupUtils.emergencyCleanup();
    };

    // Initialize Core Services Globally
    final prefs = await SharedPreferences.getInstance();
    final storageService = StorageService(prefs: prefs);
    final configManager = ConfigManager(); // Create Global Instance Here

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => ThemeProvider()),
          // Inject StorageService
          Provider<StorageService>.value(value: storageService),
          // Inject Global ConfigManager (Critical Fix)
          ChangeNotifierProvider.value(value: configManager),
          // Inject HomeProvider dependent on StorageService
          ChangeNotifierProvider(
            create: (context) => HomeProvider(storageService: storageService),
          ),
        ],
        child: const GlobalWindowListener(child: MyApp()),
      ),
    );
  }, (error, stack) {
    // Catch-all for async errors
    if (kDebugMode) {
      print('CRITICAL STARTUP ERROR: $error');
    }
    // Simple error logging to prevent total crash
    try {
      AdvancedLogger.error("UNCAUGHT ASYNC ERROR", error: error, stackTrace: stack);
      CleanupUtils.emergencyCleanup();
    } catch (_) {}
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch ThemeProvider safely
    final themeProvider = context.watch<ThemeProvider>();
    
    return MaterialApp(
      title: 'iVPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeProvider.themeMode,
      builder: (context, child) {
        return BackgroundAdService(child: child!);
      },
      // Start with Splash Screen to handle async init safely
      home: const SplashScreen(),
    );
  }
}

class GlobalWindowListener extends StatefulWidget {
  final Widget child;
  const GlobalWindowListener({super.key, required this.child});

  @override
  State<GlobalWindowListener> createState() => _GlobalWindowListenerState();
}

class _GlobalWindowListenerState extends State<GlobalWindowListener> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      _initWindow();
    }
  }

  Future<void> _initWindow() async {
    // Prevent default close to handle it manually
    await windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    print("🧹 Closing app...");
    AdvancedLogger.info("🧹 Closing app - cleaning up VPN...");

    // Kill Process
    try {
      // Create a temporary instance to stop VPN (it kills by process name)
      await WindowsVpnService().stopVpn();
    } catch (e) {
      AdvancedLogger.error("Error stopping VPN on exit: $e");
    }

    // Proceed with close
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.destroy();
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
