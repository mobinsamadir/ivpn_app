import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/advanced_logger.dart';
import 'services/file_logger.dart';
import 'services/storage_service.dart';
import 'services/config_manager.dart';
import 'utils/cleanup_utils.dart';
import 'providers/theme_provider.dart';
import 'providers/home_provider.dart';
import 'screens/connection_home_screen.dart';
import 'services/background_ad_service.dart';

void main() async {
  print('ðŸš€ IVPN App Started - ${DateTime.now()}');
  stdout.writeln('=== Debug Mode Active ===');
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize advanced logger with full debug info
  await AdvancedLogger.init();
  AdvancedLogger.info('ðŸš€ IVPN App Initialized', metadata: {
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

  PlatformDispatcher.instance.onError = (error, stack) {
    AdvancedLogger.error("GLOBAL PLATFORM ERROR", error: error, stackTrace: stack);
    CleanupUtils.emergencyCleanup();
    return true; // Handle error
  };

  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs: prefs);

  // Initialize Config Manager
  await ConfigManager().init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(
          create: (context) => HomeProvider(storageService: storageService),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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

