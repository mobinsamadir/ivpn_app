import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'utils/advanced_logger.dart';
import 'utils/file_logger.dart';
import 'services/config_manager.dart';
import 'utils/cleanup_utils.dart';
import 'providers/theme_provider.dart';
import 'services/background_ad_service.dart';
import 'screens/splash_screen.dart'; // Ensure this import exists
import 'services/windows_vpn_service.dart';

void main() {
  // 1. Ensure bindings first (Must be first)
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Fail-Safe: Inject Global Error UI immediately to prevent Black Screen on render errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: SafeArea(
        child: Container(
          color: Colors.red.shade900,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Text(
              '${details.exceptionAsString()}\n\n${details.stack}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ),
    );
  };

  runZonedGuarded(() async {
    // 3. Robust Initialization with Timeouts & Try-Catch
    // WindowManager (Desktop)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await windowManager
            .ensureInitialized()
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("WindowManager init failed or timed out: $e");
      }
    }

    // Initialize Loggers (Non-critical: Don't block app start)
    try {
      await AdvancedLogger.init().timeout(const Duration(seconds: 2));
      AdvancedLogger.info('🚀 IVPN App Initialized', metadata: {
        'platform': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
      });

      await FileLogger.init().timeout(const Duration(seconds: 2));
      FileLogger.log("Application starting...");
    } catch (e) {
      debugPrint("Logger initialization warning: $e");
    }

    // Setup Global Crash Recovery
    // FlutterError.onError = (details) {
    //   FlutterError.presentError(details);
    //   try {
    //     AdvancedLogger.error("GLOBAL FLUTTER ERROR", error: details.exception, stackTrace: details.stack);
    //     CleanupUtils.emergencyCleanup();
    //   } catch (_) {}
    // };

    // Initialize Core Services Globally
    try {
      // Critical: SharedPreferences with Timeout
      // ignore: unused_local_variable
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("CRITICAL: SharedPreferences failed to load: $e");
      // Fallback: If SharedPreferences fails, show Fatal Error Screen via runApp
      runApp(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Text(
              "Fatal Error: Storage Initialization Failed.\n$e",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ));
      return; // Stop execution
    }

    final configManager = ConfigManager(); // Create Global Instance Here

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => ThemeProvider()),
          // Inject Global ConfigManager (Critical Fix)
          ChangeNotifierProvider.value(value: configManager),
        ],
        child: const GlobalWindowListener(child: MyApp()),
      ),
    );
  }, (error, stack) {
    // Catch-all for async errors
    if (kDebugMode) {
      // ignore: avoid_print
      print('CRITICAL STARTUP ERROR: $error');
    }
    // Simple error logging to prevent total crash
    try {
      AdvancedLogger.error("UNCAUGHT ASYNC ERROR",
          error: error, stackTrace: stack);
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

class _GlobalWindowListenerState extends State<GlobalWindowListener>
    with WindowListener {
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
    // ignore: avoid_print
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
