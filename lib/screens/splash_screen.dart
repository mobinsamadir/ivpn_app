import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/config_manager.dart';
import '../services/time_wallet_service.dart';
import '../utils/advanced_logger.dart';
import '../services/ad_manager_service.dart';
import '../services/funnel_service.dart';
import 'connection_home_screen.dart';
import '../widgets/scale_on_tap.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  String _statusMessage = 'در حال آماده‌سازی...';
  bool _hasError = false;
  String? _errorMessage;

  late AnimationController _progressController;
  Timer? _messageTimer;
  int _messageIndex = 0;

  final List<String> _loadingMessages = [
    'در حال آماده‌سازی...',
    'در حال بارگذاری کانفیگ‌ها...',
    'در حال بررسی سرورها...',
    'آماده‌سازی اتصال...',
  ];

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4), // Fallback visual duration
    );

    // Start progress animation
    _progressController.forward();

    // Cycle messages every 2 seconds
    _messageTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _messageIndex = (_messageIndex + 1) % _loadingMessages.length;
          _statusMessage = _loadingMessages[_messageIndex];
        });
      }
    });

    // Run after first frame render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    setState(() {
      _hasError = false;
    });

    try {
      final configManager = context.read<ConfigManager>();
      await Permission.notification.request();

      // Ensure minimum splash time of 2 seconds
      final minSplashFuture = Future.delayed(const Duration(seconds: 2));

      await configManager.init().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AdvancedLogger.error("ConfigManager.init timed out!");
        },
      );

      FunnelService().startFunnel();
      AdManagerService().initialize();

      final timeWallet = TimeWalletService();
      await timeWallet.init();

      bool skipWait = false;
      if (timeWallet.hasTime &&
          configManager.isAutoSwitchEnabled &&
          configManager.validatedConfigs.isNotEmpty) {
        skipWait = true;
        AdvancedLogger.info(
          "[Splash] Optimistic Startup enabled. Bypassing funnel wait.",
        );
        configManager.connectWithSmartFailover();
      }

      if (!skipWait) {
        int waitLoops = 0;
        while (configManager.validatedConfigs.isEmpty && waitLoops < 10) {
          await Future.delayed(const Duration(seconds: 1));
          waitLoops++;
        }
      }

      await minSplashFuture;

      if (mounted) {
        _progressController.stop();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ConnectionHomeScreen()),
        );
      }
    } catch (e, stack) {
      AdvancedLogger.error("Splash Init Error", error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Initialization Failed:\n$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              AnimatedBuilder(
                animation: _progressController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.8 + (_progressController.value * 0.2),
                    child: Opacity(
                      opacity: 0.5 + (_progressController.value * 0.5),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38EF7D).withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.vpn_lock,
                    size: 80,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 60),

              if (_hasError) ...[
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Unknown Error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                ),
                const SizedBox(height: 24),
                ScaleOnTap(
                  onTap: _initializeApp,
                  child: IgnorePointer(
                    child: ElevatedButton.icon(
                      onPressed: _initializeApp,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Custom Progress Bar
                Container(
                  width: 200,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, child) {
                        return LinearProgressIndicator(
                          value: _progressController.value,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.greenAccent,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Rotating Message
                AnimatedSwitcher(
                  layoutBuilder:
                      (Widget? currentChild, List<Widget> previousChildren) {
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  duration: const Duration(milliseconds: 500),
                  child: Text(
                    _statusMessage,
                    key: ValueKey<String>(_statusMessage),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontFamily: 'Vazirmatn',
                    ),
                    textDirection: TextDirection.rtl,
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
