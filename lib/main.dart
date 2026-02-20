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
import 'screens/splash_screen.dart';
import 'services/windows_vpn_service.dart';
import 'services/funnel_service.dart'; // Added
import 'services/ad_manager_service.dart'; // Added

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
              details.exceptionAsString() + '\n\n' + (details.stack.toString()),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ),
    );
  };

  runApp(const AppInitializer());
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  String _bootStatus = "Initializing...";
  String? _errorMessage;
  bool _initialized = false;

  // Services
  StorageService? _storageService;
  ConfigManager? _configManager;

  @override
  void initState() {
    super.initState();
    // Run async init in a zone to catch errors
    runZonedGuarded(() {
      _initApp();
    }, (error, stack) {
      if (kDebugMode) {
        print('CRITICAL STARTUP ERROR: $error');
      }
      try {
        AdvancedLogger.error("UNCAUGHT ASYNC ERROR", error: error, stackTrace: stack);
        CleanupUtils.emergencyCleanup();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _errorMessage = "Critical Startup Error:\n$error";
        });
      }
    });
  }

  Future<void> _initApp() async {
    try {
      // 1. Window & Logger Init
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        try {
          await windowManager.ensureInitialized().timeout(const Duration(seconds: 2));
        } catch (_) {}
      }

      setState(() => _bootStatus = "1/4: Init Local DB...");

      try {
        await AdvancedLogger.init().timeout(const Duration(seconds: 2));
        await FileLogger.init().timeout(const Duration(seconds: 2));
      } catch (_) {}

      // 2. Storage Init
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      _storageService = StorageService(prefs: prefs);
      _configManager = ConfigManager(); // Create Global Instance

      // 3. Config Manager Init
      setState(() => _bootStatus = "2/4: Fetching Cloud Configs...");

      // We pass the storage service implicitly via injection later, but ConfigManager might need init
      // Note: ConfigManager usually loads from storage or cloud.

      await _configManager!.init().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AdvancedLogger.error("ConfigManager.init timed out!");
        }
      );

      // Start Funnel (Isolate sorting)
      setState(() => _bootStatus = "3/4: Sorting (Isolate)...");
      FunnelService().startFunnel();

      // 4. Ads Init
      setState(() => _bootStatus = "4/4: Init Ads...");
      AdManagerService().initialize();

      // Fetch Updates
      await _configManager!.fetchStartupConfigs().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          return false;
        }
      );

      // Complete
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e, s) {
      AdvancedLogger.error("Initialization Failed", error: e, stackTrace: s);
      if (mounted) {
        setState(() {
          _errorMessage = "Initialization Failed:\n$e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show Splash if not ready or error
    if (!_initialized || _errorMessage != null) {
      return MaterialApp(
        title: 'iVPN Boot',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: SplashScreen(
          statusMessage: _bootStatus,
          errorMessage: _errorMessage,
          onRetry: _errorMessage != null ? () {
            setState(() {
              _errorMessage = null;
              _bootStatus = "Retrying...";
            });
            _initApp();
          } : null,
        ),
      );
    }

    // Launch App Tree
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        // Inject StorageService
        Provider<StorageService>.value(value: _storageService!),
        // Inject Global ConfigManager
        ChangeNotifierProvider.value(value: _configManager!),
        // Inject HomeProvider dependent on StorageService
        ChangeNotifierProvider(
          create: (context) => HomeProvider(storageService: _storageService!),
        ),
      ],
      child: const GlobalWindowListener(child: MyApp()),
    );
  }
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
      // Direct to Home since we handled Splash in AppInitializer
      home: const ConnectionHomeScreen(),
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
