import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'utils/advanced_logger.dart'; // Corrected import
import 'services/storage_service.dart';
import 'services/config_manager.dart';
import 'utils/cleanup_utils.dart';
import 'providers/theme_provider.dart';
import 'providers/home_provider.dart';
import 'screens/connection_home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/background_ad_service.dart';
import 'screens/emergency_screen.dart';

void main() {
  runZonedGuarded(() {
    try {
      // Minimize work in main() to prevent launch timeouts (Grey Screen)
      WidgetsFlutterBinding.ensureInitialized();

      // Setup Custom Error Widget for Release Mode to prevent Grey Screen
      ErrorWidget.builder = (FlutterErrorDetails details) {
        Zone.current.handleUncaughtError(details.exception, details.stack ?? StackTrace.empty);
        return Material(
          color: Colors.red.shade900,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                'UI Rendering Error:\n${details.exception}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      };

      // Setup Global Crash Recovery (Safe to call early as long as loggers handle uninitialized state)
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        // AdvancedLogger handles uninitialized state gracefully
        AdvancedLogger.error("GLOBAL FLUTTER ERROR", error: details.exception, stackTrace: details.stack);
        CleanupUtils.emergencyCleanup();
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        AdvancedLogger.error("GLOBAL PLATFORM ERROR", error: error, stackTrace: stack);
        CleanupUtils.emergencyCleanup();
        return true; // Handle error
      };

      // Initialize Global State
      final configManager = ConfigManager();

      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: configManager),
          ],
          child: const MyApp(),
        ),
      );
    } catch (e, stack) {
      // Catch synchronous errors during initialization (e.g., ensureInitialized failure)
      // Use print as AdvancedLogger might not be initialized or might be the cause
      debugPrint("FATAL STARTUP ERROR: $e");
      try {
        AdvancedLogger.error("FATAL STARTUP ERROR", error: e, stackTrace: stack);
      } catch (_) {}

      runApp(EmergencyApp(error: e.toString()));
    }
  }, (error, stack) {
    // Catch asynchronous errors
    debugPrint("UNCAUGHT ASYNC ERROR: $error");
    try {
      AdvancedLogger.error("UNCAUGHT ASYNC ERROR", error: error, stackTrace: stack);
      CleanupUtils.emergencyCleanup();
    } catch (_) {}
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StorageService? _storageService;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
       return EmergencyApp(error: _errorMessage, onRetry: () {
         setState(() {
           _hasError = false;
           _errorMessage = '';
         });
       });
    }

    try {
      // Phase 1: Show Splash Screen & Initialize
      if (_storageService == null) {
        return MaterialApp(
          title: 'iVPN Splash',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(useMaterial3: true), // Dark theme for splash
          home: SplashScreen(
            onInitializationComplete: (storage) {
              if (mounted) {
                setState(() {
                  _storageService = storage;
                });
              }
            },
          ),
        );
      }

      // Phase 2: Show Main App with Providers injected
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(
            create: (_) => HomeProvider(storageService: _storageService!),
          ),
        ],
        child: const ThemedApp(),
      );
    } catch (e, stack) {
      AdvancedLogger.error("MyApp Build Error", error: e, stackTrace: stack);
      return EmergencyApp(error: e.toString());
    }
  }
}

class ThemedApp extends StatelessWidget {
  const ThemedApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Now we can safely access ThemeProvider
    try {
      final themeProvider = context.watch<ThemeProvider>();

      return MaterialApp(
        title: 'iVPN',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: themeProvider.themeMode,
        builder: (context, child) {
          try {
            return BackgroundAdService(child: child!);
          } catch (e) {
             AdvancedLogger.error("BackgroundAdService Error", error: e);
             return child!;
          }
        },
        home: const ConnectionHomeScreen(),
      );
    } catch (e) {
      return EmergencyApp(error: "ThemedApp Error: $e");
    }
  }
}
