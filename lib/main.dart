import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'utils/advanced_logger.dart'; // Corrected import
import 'services/storage_service.dart';
import 'utils/cleanup_utils.dart';
import 'providers/theme_provider.dart';
import 'providers/home_provider.dart';
import 'screens/connection_home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/background_ad_service.dart';

void main() {
  // Minimize work in main() to prevent launch timeouts (Grey Screen)
  WidgetsFlutterBinding.ensureInitialized();
  
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

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StorageService? _storageService;

  @override
  Widget build(BuildContext context) {
    // Phase 1: Show Splash Screen & Initialize
    if (_storageService == null) {
      return MaterialApp(
        title: 'iVPN Splash',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true), // Dark theme for splash
        home: SplashScreen(
          onInitializationComplete: (storage) {
            setState(() {
              _storageService = storage;
            });
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
  }
}

class ThemedApp extends StatelessWidget {
  const ThemedApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Now we can safely access ThemeProvider
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
      home: const ConnectionHomeScreen(),
    );
  }
}
