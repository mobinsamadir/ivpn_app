import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/config_manager.dart';
import '../services/time_wallet_service.dart';
import '../utils/advanced_logger.dart';
import '../services/ad_manager_service.dart';

import 'connection_home_screen.dart';
import '../widgets/scale_on_tap.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  String _statusMessage = 'Preparing...';
  bool _hasError = false;
  String? _errorMessage;

  late AnimationController _progressController;
  Timer? _messageTimer;
  int _messageIndex = 0;

  final List<String> _loadingMessages = [
    'Preparing...',
    'Loading servers...',
    'Checking network...',
    'Readying connection...',
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
      AdManagerService().initialize();

      final timeWallet = TimeWalletService();
      await timeWallet.init();

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
              // Branded Logo
              AnimatedBuilder(
                animation: _progressController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.9 + (_progressController.value * 0.1),
                    child: Opacity(
                      opacity: 0.7 + (_progressController.value * 0.3),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1F2937), Color(0xFF111827)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38EF7D).withValues(alpha: 0.25),
                        blurRadius: 32,
                        spreadRadius: 4,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(
                      color: const Color(0xFF38EF7D).withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Image.asset(
                    'assets/icon.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.shield_rounded,
                      size: 64,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              // Brand Name & Tagline
              const Text(
                'iVPN',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'High Speed • Secure • Borderless',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 48),

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
                      onPressed: () {},
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
                  width: 220,
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
                const SizedBox(height: 20),
                // Rotating Message
                AnimatedSwitcher(
                  layoutBuilder:
                      (Widget? currentChild, List<Widget> previousChildren) {
                    return Stack(
                      alignment: Alignment.center,
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
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  'v2.0.0',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 11,
                    letterSpacing: 1.0,
                    fontFamily: 'monospace',
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
