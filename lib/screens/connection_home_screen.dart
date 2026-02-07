import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import '../models/vpn_config_with_metrics.dart';
import '../providers/home_provider.dart';
import '../services/config_manager.dart';
import '../services/latency_service.dart';
import '../services/windows_vpn_service.dart';
import '../widgets/smart_connect_button.dart';
import '../widgets/ad_banner_webview.dart';
import '../widgets/config_list_tabs.dart';
import '../utils/advanced_logger.dart';
import '../utils/clipboard_utils.dart';
import '../services/config_importer.dart';
import 'stability_chart_screen.dart';
import 'log_viewer_screen.dart';
import '../services/access_manager.dart';
import '../widgets/ad_dialog.dart';
import '../widgets/native_ad_banner.dart';
import '../services/server_tester_service.dart';

class ConnectionHomeScreen extends StatefulWidget {
  const ConnectionHomeScreen({super.key});

  @override
  State<ConnectionHomeScreen> createState() => _ConnectionHomeScreenState();
}

class _ConnectionHomeScreenState extends State<ConnectionHomeScreen> with WidgetsBindingObserver {
  // 1. Initialize services IMMEDIATELY
  final WindowsVpnService _windowsVpnService = WindowsVpnService();
  late final LatencyService _latencyService;

  // 2. State Variables
  final ConfigManager _configManager = ConfigManager();
  bool _isInitialized = false;
  bool _autoTestOnStartup = true;
  bool _isWatchingAd = false;
  final List<String> _connectionLogs = [];
  Timer? _timerUpdater;
  final Set<String> _activeTestIds = {};

  // Parallel Intelligence Variables
  VpnConfigWithMetrics? _fastestInBackground;
  bool _showFastestOverlay = false;
  Timer? _backgroundTestTimer;

  // Auto-switch Variables
  int _highPingCounter = 0;
  static const int _highPingThreshold = 2000; // ms
  static const int _consecutiveHighPingCount = 2; // consecutive checks before switching
  Timer? _pingMonitorTimer;

  @override
  void initState() {
    _latencyService = LatencyService(_windowsVpnService);
    super.initState();

    _initialize();
    WidgetsBinding.instance.addObserver(this);

    // AccessManager Listener
    AccessManager().init().then((_) {
      if (mounted) setState(() {});
    });
    AccessManager().addListener(_onTimeChanged);

    // Fire and forget: fetch startup configs from GitHub
    _configManager.fetchStartupConfigs();

    // VPN Connection Status Listener
    _windowsVpnService.statusStream.listen((status) {
      AdvancedLogger.info('[ConnectionHomeScreen] Received VPN status update: $status');
      if (mounted) {
        setState(() {
          // Update the connection status in ConfigManager to reflect the actual VPN status
          _configManager.setConnected(status == 'CONNECTED', status: _getConnectionStatusMessage(status));
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAppSequence();
    });

    _timerUpdater = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });

    // Start ping monitoring for auto-switch
    _startPingMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AccessManager().removeListener(_onTimeChanged);
    _timerUpdater?.cancel();
    _backgroundTestTimer?.cancel();
    _pingMonitorTimer?.cancel();
    super.dispose();
  }

  // Start ping monitoring for auto-switch functionality
  void _startPingMonitoring() {
    _pingMonitorTimer?.cancel();
    _pingMonitorTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkForHighPingAndAutoSwitch();
    });
  }

  // Check for high ping and auto-switch if needed
  void _checkForHighPingAndAutoSwitch() async {
    if (!_configManager.isAutoSwitchEnabled) {
      // Reset counter when auto-switch is disabled
      _highPingCounter = 0;
      return;
    }

    if (!_configManager.isConnected) {
      // Reset counter when not connected
      _highPingCounter = 0;
      return;
    }

    // Check if current ping is high
    if (_configManager.isCurrentPingHigh()) {
      _highPingCounter++;
      AdvancedLogger.info('[ConnectionHomeScreen] High ping detected. Counter: $_highPingCounter');

      // If high ping has been detected for consecutive checks, initiate auto-switch
      if (_highPingCounter >= _consecutiveHighPingCount) {
        await _performAutoSwitch();
        _highPingCounter = 0; // Reset counter after switching
      }
    } else {
      // Reset counter if ping is not high
      _highPingCounter = 0;
    }
  }

  // Perform auto-switch to best server
  Future<void> _performAutoSwitch() async {
    AdvancedLogger.info('[ConnectionHomeScreen] Initiating auto-switch due to high ping');
    _showToast("High ping detected. Switching to best server...");

    try {
      // Stop current VPN connection
      await _windowsVpnService.stopVpn();

      // ADD THIS DELAY: Cool-down period to allow OS to release TUN interface
      AdvancedLogger.info('Waiting for port release...');
      await Future.delayed(const Duration(seconds: 1)); // Cool-down period

      // Find the fastest server
      final newConfig = await _findFastestServerEager();
      if (newConfig != null) {
        // Update selected config
        _configManager.selectConfig(newConfig);

        // Reconnect with the new config
        await _handleConnection();
      } else {
        _showToast("Could not find a better server to switch to");
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error('[ConnectionHomeScreen] Auto-switch failed: $e', error: e, stackTrace: stackTrace);
      _showToast("Auto-switch failed: $e");
    }
  }

  void _onTimeChanged() {
    if (mounted) setState(() {});
  }

  String _getConnectionStatusMessage(String status) {
    switch (status) {
      case 'CONNECTED':
        return 'Connected';
      case 'CONNECTING':
        return 'Connecting...';
      case 'DISCONNECTED':
        return 'Disconnected';
      case 'ERROR':
        return 'Connection Error';
      default:
        return status;
    }
  }

  Color _getPingColor(int ping) {
    if (ping < 150) {
      return Colors.green.shade700; // Green for low ping
    } else if (ping < 400) {
      return Colors.yellow.shade700; // Yellow for medium ping
    } else {
      return Colors.red.shade700; // Red for high ping
    }
  }
  
  // --- AD REWARD LOGIC ---
  Future<void> _showAdSequence() async {
    // Step 1: Explanation Dialog
    final engage = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Add 1 Hour Time', style: TextStyle(color: Colors.white)),
        content: const Text(
          'To keep the service free, please engage with our sponsor.\n\n'
          '1. Click "View Ad"\n'
          '2. Wait 5 seconds\n'
          '3. Close the ad and claim your reward.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('View Ad', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (engage == true) {
      if (!mounted) return;

      // Step 2: Show Internal Ad Dialog with WebView
      const adUrl = "https://ad.a-ads.com/2426527";

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AdDialog(adUrl: adUrl),
      );

      if (!mounted) return;

      // Step 3: Reward Claim Dialog
      final claimed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Claim Reward', style: TextStyle(color: Colors.white)),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.card_giftcard, size: 60, color: Colors.amber),
              SizedBox(height: 16),
              Text(
                'Thank you for supporting us!\nClaim your 1 hour of VPN time?',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Claim +1 Hour', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (claimed == true) {
        await AccessManager().addTime(const Duration(hours: 1));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Success! +1 Hour Added."),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  Future<void> _initAppSequence() async {
    if (!mounted) return;
    setState(() {});

    if (_autoTestOnStartup && mounted) {
       _runSmartAutoTest();
    }
  }

  Future<void> _runSmartAutoTest() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    
    if (_configManager.allConfigs.isEmpty) {
        int attempts = 0;
        while (_configManager.allConfigs.isEmpty && attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 500));
          attempts++;
        }
    }

    if (_configManager.allConfigs.isEmpty) return;

    AdvancedLogger.info("🚀 [Startup] Running Smart Auto-Test...");
    await _runFunnelTest(_configManager.allConfigs);
    
    _configManager.allConfigs.sort((a, b) {
        final pingA = a.currentPing > 0 ? a.currentPing : 999999;
        final pingB = b.currentPing > 0 ? b.currentPing : 999999;
        return pingA.compareTo(pingB);
    });

    if (mounted) {
       setState(() {});
       final best = _configManager.allConfigs.first;
       if (best.currentPing > 0 && best.currentPing < 999999) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Best Server Found: ${best.name} (${best.currentPing}ms)'),
              backgroundColor: Colors.green[700],
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
       }
    }
  }

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() {
      _connectionLogs.add(msg);
    });
  }

  Future<void> _runSelfDiagnostics() async {
    try {
      AdvancedLogger.info("🔍 Running system diagnostics...");

      if (_windowsVpnService == null) {
        AdvancedLogger.error("❌ SYSTEMS CHECK: WindowsVpnService not initialized");
        return;
      }
      if (_latencyService == null) {
        AdvancedLogger.error("❌ SYSTEMS CHECK: LatencyService not initialized");
        return;
      }

      try {
        final executablePath = await _windowsVpnService.getExecutablePath();
        AdvancedLogger.info("✅ SYSTEMS CHECK: Sing-box executable found at: $executablePath");
      } catch (e) {
        AdvancedLogger.error("❌ SYSTEMS CHECK: Sing-box executable not found - $e");
        return;
      }

      const dummyConfig = "vmess://dummy@127.0.0.1:1?dummy=true#DummyTest";
      final timeoutFuture = _latencyService.getAdvancedLatency(dummyConfig).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Latency test timed out'),
      );

      try {
        await timeoutFuture;
        AdvancedLogger.error("❌ SYSTEMS CHECK: Latency test should have failed with dummy config but didn't");
      } catch (e) {
        if (e is TimeoutException) {
          AdvancedLogger.error("❌ SYSTEMS CHECK: Latency test timed out - service may be hanging");
        } else {
          AdvancedLogger.info("✅ SYSTEMS CHECK: Latency service is responsive (expected failure with dummy config)");
        }
      }
      AdvancedLogger.info("✅ SYSTEMS CHECK: PASSED - All services initialized and responsive");
    } catch (e) {
      AdvancedLogger.error("❌ SYSTEMS CHECK: FAILED with error - $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Lifecycle handling if needed
  }

  Future<void> _initialize() async {
    try {
      if (!_isInitialized) {
        setState(() {
          _isInitialized = true;
        });
      }
      AdvancedLogger.info('[HomeScreen] Initialized successfully');
    } catch (e) {
      AdvancedLogger.error('[HomeScreen] Initialization failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // 1. TOP STICKY SECTION: Ad banner
            _buildAdBannerSection(),

            // 2. SCROLLABLE CONTENT SECTION
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // App Header & Main Controls
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        children: [
                          _buildAppHeader(),
                          const SizedBox(height: 8),
                          _buildSubscriptionCard(), 
                          const SizedBox(height: 16),
                          _buildConnectionStatus(),
                          const SizedBox(height: 12),

                          _buildConnectButton(),
                          const SizedBox(height: 30),
                          _buildSelectedConfig(),
                          const SizedBox(height: 25),
                          _buildAutoTestToggle(),
                          const SizedBox(height: 30),

                          // Native Ad Banner
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: NativeAdBanner(key: Key('native_ad_banner')),
                          ),
                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.greenAccent),
                              ),
                              onPressed: () {
                                final selected = _configManager.selectedConfig;
                                if (selected == null) {
                                  _showToast('Please select a server first');
                                  return;
                                }
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => StabilityChartScreen(rawConfig: selected.rawConfig),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.monitor_heart, color: Colors.greenAccent),
                              label: const Text('Open 30s Stability Test'),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // "Switch to Faster" Overlay - appears when a faster server is found
                    if (_showFastestOverlay && _fastestInBackground != null)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.green.shade700, Colors.green.shade900],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              // Switch to the faster server
                              _configManager.selectConfig(_fastestInBackground);
                              setState(() {
                                _showFastestOverlay = false;
                              });
                              _showToast("Switched to ${_fastestInBackground!.name} (${_fastestInBackground!.currentPing}ms)");
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Icon(Icons.flash_on, color: Colors.amber, size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '⚡ Fastest Server Found!',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Switch to ${_fastestInBackground!.name} (${_fastestInBackground!.currentPing}ms)',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Server List Section
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 5,
                            offset: const Offset(0, -5),
                          ),
                        ],
                        border: Border.all(
                          color: const Color(0xFF2A2A2A),
                          width: 1,
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                          child: ConfigListTabs(
                            key: const Key('server_list_view'),
                            onConfigTapped: (config) {
                              setState(() {});
                            },
                            onTestLatency: _runSingleLatencyTest,
                            onTestSpeed: _runSingleSpeedTest,
                            onTestStability: _runSingleStabilityTest,
                            onTestAll: _runSmartAutoTest,
                            onRefresh: _refreshConfigsFromGitHub,
                            testingIds: _activeTestIds,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdBannerSection() {
    return const SizedBox(
      height: 80,
      width: double.infinity,
      child: AdBannerWebView(key: Key('top_banner_webview')),
    );
  }

  Widget _buildAppHeader() {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VPN Manager',
              style: TextStyle(
                color: Colors.grey[100],
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Secure & Fast Connections',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
          ],
        ),
        const Spacer(),
        Row(
          children: [
            _buildIconButton(
              key: const Key('smart_paste_button'),
              icon: Icons.content_paste,
              onPressed: _handleSmartPaste,
              tooltip: 'Smart Paste',
            ),
            const SizedBox(width: 12),
            _buildIconButton(
              icon: Icons.terminal,
              onPressed: _openLogViewer,
              tooltip: 'View Logs',
            ),
            const SizedBox(width: 12),
            ListenableBuilder(
              listenable: _configManager,
              builder: (context, _) {
                return _buildIconButton(
                  key: const Key('refresh_button'),
                  icon: _configManager.isRefreshing
                    ? Icons.hourglass_empty
                    : Icons.refresh,
                  onPressed: _configManager.isRefreshing
                    ? () {}
                    : () => _configManager.refreshAllConfigs(),
                  tooltip: _configManager.isRefreshing
                    ? 'Refreshing...'
                    : 'Refresh Configs',
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIconButton({
    Key? key,
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.grey[300], size: 20),
        tooltip: tooltip,
        splashRadius: 20,
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.greenAccent.withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connection Status',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Consumer<HomeProvider>(
                  builder: (context, homeProvider, child) {
                    return Text(
                      _configManager.connectionStatus,
                      key: const Key('connection_status_text'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
                Consumer<HomeProvider>(
                  builder: (context, homeProvider, child) {
                    if (_configManager.isConnected) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'Time remaining: ${homeProvider.formattedRemainingTime}',
                          style: TextStyle(
                            color: Colors.amber[300],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  },
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _showConnectionInfo,
            icon: Icon(Icons.info_outline, color: Colors.grey[500]),
            tooltip: 'Connection Info',
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1A1A).withValues(alpha: 0.8),
            const Color(0xFF0F0F0F).withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main Connect/Disconnect Button (Larger and more prominent)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A).withOpacity(0.7),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A1A1A).withOpacity(0.8),
                  const Color(0xFF0F0F0F).withOpacity(0.8),
                ],
              ),
            ),
            child: Column(
              children: [
                // Main Connect/Disconnect Button with State-Based Styling (Increased size)
                AnimatedBuilder(
                  animation: _configManager,
                  builder: (context, child) {
                    Color buttonColor;
                    IconData iconData;
                    String tooltipText;

                    if (_configManager.isConnected) {
                      // CONNECTED state
                      buttonColor = Colors.greenAccent;
                      iconData = Icons.shield;
                      tooltipText = 'Connected - Protected';
                    } else if (_configManager.connectionStatus == 'Connecting...') {
                      // CONNECTING state
                      buttonColor = Colors.yellow;
                      iconData = Icons.autorenew;
                      tooltipText = 'Connecting - Securing...';
                    } else {
                      // IDLE state
                      buttonColor = Colors.grey.shade600;
                      iconData = Icons.power_settings_new;
                      tooltipText = 'Start Protection';
                    }

                    return Container(
                      key: const Key('connect_button'),
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: buttonColor,
                        boxShadow: [
                          BoxShadow(
                            color: buttonColor.withOpacity(0.4),
                            blurRadius: 15,
                            spreadRadius: 3,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: AnimatedRotation(
                        turns: _configManager.connectionStatus == 'Connecting...' ? 0.5 : 0,
                        duration: const Duration(milliseconds: 500),
                        child: IconButton(
                          icon: Icon(
                            iconData,
                            color: Colors.white,
                            size: 60, // Increased icon size proportionally
                          ),
                          tooltip: tooltipText,
                          onPressed: _handleMainButtonAction,
                        ),
                      ),
                    );
                  },
                ),
                // Live Connection Health - Ping Display
                if (_configManager.isConnected && _configManager.selectedConfig != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getPingColor(_configManager.selectedConfig!.currentPing),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_configManager.selectedConfig!.currentPing}ms',
                      key: const Key('ping_display_text'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 25), // Increased spacing
          // Secondary Actions Row (Smaller buttons)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Fastest Button - moved to secondary row with smaller size
              Container(
                key: const Key('find_fastest_button'),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.deepPurple,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.bolt, color: Colors.white, size: 18),
                  tooltip: 'Find Fastest Server',
                  onPressed: _findFastestServer,
                ),
              ),
              // Favorite Button - restored to secondary row
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _configManager.selectedConfig?.isFavorite == true ? Colors.red : Colors.grey.shade700,
                  boxShadow: [
                    BoxShadow(
                      color: (_configManager.selectedConfig?.isFavorite == true ? Colors.red : Colors.grey.shade700).withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    _configManager.selectedConfig?.isFavorite == true ? Icons.favorite : Icons.favorite_border,
                    color: Colors.white,
                    size: 20,
                  ),
                  tooltip: _configManager.selectedConfig?.isFavorite == true ? 'Remove from Favorites' : 'Add to Favorites',
                  onPressed: _toggleFavorite,
                ),
              ),
              // Auto-Switch Toggle Button (Reduced size)
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _configManager.isAutoSwitchEnabled ? Colors.orange : Colors.grey.shade700,
                  boxShadow: [
                    BoxShadow(
                      color: (_configManager.isAutoSwitchEnabled ? Colors.orange : Colors.grey.shade700).withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    _configManager.isAutoSwitchEnabled ? Icons.auto_mode : Icons.auto_mode_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  tooltip: _configManager.isAutoSwitchEnabled
                      ? 'Auto-Switch Enabled: Will switch to best server when ping is high'
                      : 'Auto-Switch Disabled: Tap to enable automatic server switching',
                  onPressed: () {
                    _configManager.isAutoSwitchEnabled = !_configManager.isAutoSwitchEnabled;
                    _showToast(_configManager.isAutoSwitchEnabled
                        ? 'Auto-Switch enabled'
                        : 'Auto-Switch disabled');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          AnimatedBuilder(
            animation: _configManager,
            builder: (context, child) {
              String labelText;
              if (_configManager.isConnected) {
                labelText = 'Protected';
              } else if (_configManager.connectionStatus == 'Connecting...') {
                labelText = 'Securing...';
              } else {
                labelText = 'Start Protection';
              }
              return Text(
                _isWatchingAd ? 'Watching Ad...' : labelText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedConfig() {
    final selected = _configManager.selectedConfig;

    if (selected == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.amber.withOpacity(0.1),
              Colors.orange.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, color: Colors.amber[300], size: 22),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Smart Connect Active',
                    style: TextStyle(
                      color: Colors.amber[100],
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Best configuration will be automatically selected',
                    style: TextStyle(
                      color: Colors.amber.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A237E).withOpacity(0.2),
            const Color(0xFF311B92).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blueAccent.withOpacity(0.3),
                      Colors.indigo.withOpacity(0.2),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.vpn_key, color: Colors.blueAccent, size: 24),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.name,
                      key: const Key('selected_server_name'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildMetricChip(
                          icon: Icons.network_ping,
                          value: '${selected.currentPing}ms',
                          color: Colors.greenAccent,
                        ),
                        const SizedBox(width: 10),
                        _buildMetricChip(
                          icon: Icons.speed,
                          value: '${selected.currentSpeed.toStringAsFixed(1)}Mb/s',
                          color: Colors.orangeAccent,
                        ),
                        const SizedBox(width: 10),
                        _buildMetricChip(
                          icon: Icons.security,
                          value: 'Secure',
                          color: Colors.purpleAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    onPressed: () async {
                      final selected = _configManager.selectedConfig;
                      if (selected != null) {
                        await _configManager.toggleFavorite(selected.id);
                        setState(() {});
                      } else {
                        _showToast('Please select a config first');
                      }
                    },
                    icon: Icon(
                      _configManager.selectedConfig?.isFavorite == true
                          ? Icons.star
                          : Icons.star_border_outlined,
                      color: _configManager.selectedConfig?.isFavorite == true
                          ? Colors.amber
                          : Colors.grey[500],
                    ),
                    tooltip: 'Toggle Favorite',
                    splashRadius: 20,
                  ),
                  IconButton(
                    onPressed: () {
                      _configManager.selectConfig(null);
                      setState(() {});
                    },
                    icon: Icon(Icons.close, color: Colors.grey[500]),
                    tooltip: 'Clear Selection',
                    splashRadius: 20,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoTestToggle() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.blueAccent, size: 22),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto Test on Startup',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Automatically test connections when app starts',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch.adaptive(
              value: _autoTestOnStartup,
              onChanged: _toggleAutoTestOnStartup,
              activeColor: Colors.greenAccent,
              inactiveTrackColor: Colors.grey[700],
              trackOutlineColor: MaterialStateProperty.resolveWith<Color?>(
                (Set<MaterialState> states) {
                  if (states.contains(MaterialState.selected)) {
                    return Colors.greenAccent.withOpacity(0.5);
                  }
                  return Colors.grey[700];
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper Methods
  Future<void> _handleSmartPaste() async {
    try {
      final clipboardText = await ClipboardUtils.getText();

      if (clipboardText.isEmpty) {
        _showToast('Clipboard is empty');
        return;
      }

      // Show loading indicator while processing
      _showToast('Processing clipboard content...');
      
      // Use the enhanced method that handles both configs and subscription links
      final configs = await ConfigManager.parseAndFetchConfigs(clipboardText);

      if (configs.isNotEmpty) {
        // Count added configs
        int importedCount = 0;
        for (final config in configs) {
          try {
            final name = ConfigImporter.extractName(config, index: importedCount);
            await _configManager.addConfig(config, name);
            importedCount++;
          } catch (e) {
            AdvancedLogger.error('[HomeScreen] Error adding config: $e');
            continue;
          }
        }

        if (importedCount > 0) {
          _showToast('$importedCount servers added successfully');
          setState(() {});
          await _configManager.refreshAllConfigs();
        } else {
          _showToast('No valid configs found in clipboard content');
        }
      } else {
        // If no configs were found via the enhanced method, try the old single config approach
        if (ClipboardUtils.validateConfig(clipboardText)) {
          final name = ConfigImporter.extractName(clipboardText);
          await _configManager.addConfig(clipboardText, name);
          _showToast('Config imported successfully');
          setState(() {});
          await _configManager.refreshAllConfigs();
        } else {
          _showToast('No valid configs found in clipboard content');
        }
      }
    } catch (e) {
      _showToast('Error processing clipboard: $e');
      AdvancedLogger.error('[HomeScreen] Smart Paste Error: $e');
    }
  }

  Future<void> _tryParseMultipleConfigs(String text) async {
    // Use the enhanced method that handles both configs and subscription links
    final configs = await ConfigManager.parseAndFetchConfigs(text);

    int importedCount = 0;
    for (final config in configs) {
      try {
        final name = ConfigImporter.extractName(config, index: importedCount);
        await _configManager.addConfig(config, name);
        importedCount++;
      } catch (e) {
        AdvancedLogger.error('[HomeScreen] Error adding config in _tryParseMultipleConfigs: $e');
        continue;
      }
    }

    if (importedCount > 0) {
      _showToast('$importedCount configs imported successfully');
      setState(() {});
      await _configManager.refreshAllConfigs();
    } else {
      _showToast('No valid configs found in clipboard content');
    }
  }

  void _showToast(String message) {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }

  Future<void> _handleTestConnection() async {
    final selectedConfig = _configManager.selectedConfig;
    if (selectedConfig == null) {
      _showToast('Please select a config first');
      return;
    }

    _configManager.setConnected(_configManager.isConnected, status: 'Testing connection...');

    try {
      final result = await _latencyService.getAdvancedLatency(selectedConfig.rawConfig);
      final latency = result.health.averageLatency;

      await _configManager.updateConfigMetrics(
        selectedConfig.id,
        ping: latency,
        connectionSuccess: latency > 0,
      );

      _showToast('Connection test completed: ${latency}ms');
      _configManager.setConnected(_configManager.isConnected, status: 'Tested: ${latency}ms');
    } catch (e) {
      _showToast('Connection test failed: $e');
      _configManager.setConnected(_configManager.isConnected, status: 'Test failed');
      AdvancedLogger.error('[HomeScreen] Connection test failed: $e');
    }
  }

  Future<void> _handleTestStability() async {
    final selectedConfig = _configManager.selectedConfig;
    if (selectedConfig == null) {
      _showToast('Please select a config first');
      return;
    }

    _configManager.setConnected(_configManager.isConnected, status: 'Testing stability...');

    try {
      final result = await _latencyService.getAdvancedLatency(selectedConfig.rawConfig);
      final latency = result.health.averageLatency;

      await _configManager.updateConfigMetrics(
        selectedConfig.id,
        ping: latency,
        connectionSuccess: latency > 0,
      );

      _showToast('Stability test completed: ${latency}ms');
      _configManager.setConnected(_configManager.isConnected, status: 'Stability: ${latency}ms');
    } catch (e) {
      _showToast('Stability test failed: $e');
      _configManager.setConnected(_configManager.isConnected, status: 'Test failed');
      AdvancedLogger.error('[HomeScreen] Stability test failed: $e');
    }
  }

  void _toggleAutoTestOnStartup(bool value) {
    setState(() {
      _autoTestOnStartup = value;
    });
  }

  void _testAllConfigs() {
    _showToast('Testing all configurations...');
    _runFunnelTest(_configManager.allConfigs);
  }

  // NEW: Run the advanced funnel test using ServerTesterService
  Future<void> _runFunnelTest(List<VpnConfigWithMetrics> configs) async {
    if (configs.isEmpty) return;

    // Use the new ServerTesterService for advanced funnel testing
    final tester = ServerTesterService(_windowsVpnService);
    await tester.runFunnelTest(configs);
  }

  Future<void> _testAllConfigsInternal(List<VpnConfigWithMetrics> configs) async {
    if (configs.isEmpty) return;

    if (Platform.isWindows) {
       try { await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']); } catch (e) {}
    }

    const int maxConcurrency = 5;
    int successCount = 0;
    int failCount = 0;
    int nextIndex = 0;
    
    final List<VpnConfigWithMetrics> snapshot = List.from(configs);
    
    Future<void> worker() async {
      while (nextIndex < snapshot.length) {
        final config = snapshot[nextIndex++];
        
        if (mounted) {
          setState(() {
            _activeTestIds.add(config.id);
          });
        }

        try {
          if (_configManager.getConfigById(config.id) == null) {
            AdvancedLogger.info('[TestAll] Skipping deleted config: ${config.name}');
            continue;
          }

          AdvancedLogger.info('[TestAll] Testing: ${config.name}');
          final result = await _latencyService.getAdvancedLatency(
            config.rawConfig,
            configId: config.id,
            timeout: const Duration(seconds: 35),
            isPriority: false,
          );
          
          final latency = result.health.averageLatency;
          if (latency > -1) {
            successCount++;
          } else {
            failCount++;
          }

          await _configManager.updateConfigMetrics(
            config.id,
            ping: latency,
            connectionSuccess: latency > 0,
          );
        } catch (e) {
          failCount++;
          AdvancedLogger.error('[TestAll] Failed to test ${config.name}: $e');
        } finally {
          if (mounted) {
            setState(() {
              _activeTestIds.remove(config.id);
            });
          }
          
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    }

    final List<Future<void>> workers = [];
    final int workerCount = snapshot.length < maxConcurrency ? snapshot.length : maxConcurrency;
    
    for (int i = 0; i < workerCount; i++) {
      workers.add(worker());
    }
    
    await Future.wait(workers);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test Complete: $successCount Active, $failCount Failed'),
          backgroundColor: successCount >= failCount ? Colors.green[800] : Colors.red[800],
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Find the fastest server without connecting
  Future<void> _findFastestServer() async {
    if (_configManager.allConfigs.isEmpty) {
      _showToast("No configurations available. Please refresh.");
      return;
    }

    _showToast("Finding fastest server...");

    // Sort configs by ping to find the fastest
    _configManager.allConfigs.sort((a, b) {
      final pingA = a.currentPing > 0 ? a.currentPing : 999999;
      final pingB = b.currentPing > 0 ? b.currentPing : 999999;
      return pingA.compareTo(pingB);
    });

    final bestConfig = _configManager.allConfigs.firstWhere(
      (config) => config.currentPing > 0 && config.currentPing < 999999,
      orElse: () => _configManager.allConfigs.first,
    );

    if (bestConfig.currentPing > 0 && bestConfig.currentPing < 999999) {
      _configManager.selectConfig(bestConfig);
      _showToast("Fastest server selected: ${bestConfig.name} (${bestConfig.currentPing}ms)");
    } else {
      // No server responded to ping, show dialog asking user to check internet
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Internet Connection Issue', style: TextStyle(color: Colors.white)),
          content: const Text(
            'No servers responded to ping. Please check your internet connection and try again.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        ),
      );
      _showToast("No responsive servers found. Check your internet connection.");
    }
  }

  // Connect to the selected server (or find fastest if none selected) with Parallel Intelligence
  Future<void> _handleConnection() async {
    AdvancedLogger.info('[ConnectionHomeScreen] _handleConnection called');

    final homeProvider = Provider.of<HomeProvider>(context, listen: false);
    AdvancedLogger.info('[ConnectionHomeScreen] Current connection status: isConnected=${homeProvider.isConnected}, connectionStatus=${homeProvider.connectionStatus}');

    if (homeProvider.isConnected || homeProvider.connectionStatus == ConnectionStatus.connecting) {
      AdvancedLogger.info('[ConnectionHomeScreen] Already connected or connecting, stopping VPN');
      await _windowsVpnService.stopVpn();
    } else {
      // Check admin privileges before attempting connection (Windows only)
      if (Platform.isWindows) {
        try {
          final isAdmin = await _windowsVpnService.isAdmin();
          if (!isAdmin) {
            AdvancedLogger.error('[ConnectionHomeScreen] Administrator privileges required for VPN connection');
            _showToast("Administrator privileges required. Please run the app as Administrator.");

            // Show a dialog explaining the issue
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                title: const Text('Administrator Rights Required', style: TextStyle(color: Colors.white)),
                content: const Text(
                  'This VPN application requires administrator privileges to create a secure tunnel. '
                  'Please close the app and run it as Administrator.',
                  style: TextStyle(color: Colors.grey),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK', style: TextStyle(color: Colors.blueAccent)),
                  ),
                ],
              ),
            );
            return;
          }
        } catch (e) {
          AdvancedLogger.error('[ConnectionHomeScreen] Failed to check admin privileges: $e');
          _showToast("Failed to verify admin privileges: $e");
          return;
        }
      }

      // Set connection status to connecting to update UI
      AdvancedLogger.info('[ConnectionHomeScreen] Setting connection status to Connecting...');
      _configManager.setConnected(false, status: 'Connecting...');

      // Show ad automatically during connection process (without user confirmation)
      final access = AccessManager();
      AdvancedLogger.info('[ConnectionHomeScreen] Checking access: hasAccess=${access.hasAccess}');

      if (!access.hasAccess) {
        AdvancedLogger.info('[ConnectionHomeScreen] No access, showing ad sequence');
        await _showAdSequence();
        if (!access.hasAccess) {
          // User cancelled ad or didn't gain access
          AdvancedLogger.info('[ConnectionHomeScreen] No access after ad sequence, returning');
          return;
        }
      }

      AdvancedLogger.info('[ConnectionHomeScreen] Checking if configs are available. Count: ${_configManager.allConfigs.length}');
      if (_configManager.allConfigs.isEmpty) {
        _showToast("No configurations available. Please refresh.");
        AdvancedLogger.error('[ConnectionHomeScreen] No configurations available');
        return;
      }

      var targetConfig = _configManager.selectedConfig;
      AdvancedLogger.info('[ConnectionHomeScreen] Selected config: ${targetConfig?.name ?? "None"}');

      // If no server is selected, run the fastest logic first, then connect
      if (targetConfig == null) {
        AdvancedLogger.info('[ConnectionHomeScreen] No config selected, finding fastest server');
        // EAGER START: Connect to first config with ping < 1200ms
        targetConfig = await _findFastestServerEager();

        // BACKGROUND TEST: Continue testing all configs in background
        _startBackgroundTesting(targetConfig);
      }

      if (targetConfig == null) {
        AdvancedLogger.error('[ConnectionHomeScreen] Target config is null, cannot proceed with connection');
        return;
      }

      // Attempt to connect with auto-failover
      await _connectWithFailover(targetConfig);
    }
  }

  /// Connect to a server with automatic failover to the next best server
  Future<void> _connectWithFailover(VpnConfigWithMetrics? initialConfig) async {
    if (initialConfig == null) return; // Add this check!

    VpnConfigWithMetrics currentConfig = initialConfig; // Now safe
    int attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      try {
        setState(() {
          _configManager.setConnected(false, status: 'Connecting to ${currentConfig.name} (Attempt ${attempts + 1}/$maxAttempts)...');
        });

        AdvancedLogger.info('[ConnectionHomeScreen] Calling _windowsVpnService.startVpn with config: ${currentConfig.name}');
        await _windowsVpnService.startVpn(currentConfig.rawConfig);

        // Update metrics
        _configManager.updateConfigMetrics(
          currentConfig.id,
          connectionSuccess: true,
        );

        // Mark success
        await _configManager.markSuccess(currentConfig.id);

        AdvancedLogger.info('[ConnectionHomeScreen] Successfully initiated VPN connection to: ${currentConfig.name}');
        return; // Success, exit the loop

      } catch (e, stackTrace) {
        AdvancedLogger.error('[ConnectionHomeScreen] Connection failed: $e', error: e, stackTrace: stackTrace);
        
        // Mark failure for the current config
        await _configManager.markFailure(currentConfig.id);

        attempts++;
        if (attempts >= maxAttempts) {
          // No more attempts, show error
          _showToast('Connection failed after $maxAttempts attempts: $e');
          _configManager.setConnected(false, status: 'Connection failed');
          return;
        }

        // Find next best server
        final nextBest = _configManager.findBestServer();
        if (nextBest != null && nextBest.id != currentConfig.id) {
          _showToast('Connection to ${currentConfig.name} failed. Trying ${nextBest.name}...');
          currentConfig = nextBest;
        } else {
          // No other servers available, show error
          _showToast('Connection failed: $e');
          _configManager.setConnected(false, status: 'Connection failed');
          return;
        }
      }
    }
  }

  // Find the fastest server with EAGER START logic
  Future<VpnConfigWithMetrics?> _findFastestServerEager() async {
    if (_configManager.allConfigs.isEmpty) {
      _showToast("No configurations available. Please refresh.");
      return null;
    }

    _showToast("Finding fastest server...");

    // Sort configs by ping to find the fastest
    _configManager.allConfigs.sort((a, b) {
      final pingA = a.currentPing > 0 ? a.currentPing : 999999;
      final pingB = b.currentPing > 0 ? b.currentPing : 999999;
      return pingA.compareTo(pingB);
    });

    // EAGER START: Find first config with ping < 1200ms
    final fastestConfig = _configManager.allConfigs.firstWhere(
      (config) => config.currentPing > 0 && config.currentPing < 1200,
      orElse: () => _configManager.allConfigs.firstWhere(
        (config) => config.currentPing > 0,
        orElse: () => _configManager.allConfigs.first,
      ),
    );

    if (fastestConfig.currentPing > 0 && fastestConfig.currentPing < 1200) {
      _configManager.selectConfig(fastestConfig);
      _showToast("Eager start: ${fastestConfig.name} (${fastestConfig.currentPing}ms)");
      return fastestConfig;
    } else if (fastestConfig.currentPing > 0) {
      _configManager.selectConfig(fastestConfig);
      _showToast("Fastest server selected: ${fastestConfig.name} (${fastestConfig.currentPing}ms)");
      return fastestConfig;
    } else {
      // No server responded to ping, show dialog asking user to check internet
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Internet Connection Issue', style: TextStyle(color: Colors.white)),
          content: const Text(
            'No servers responded to ping. Please check your internet connection and try again.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        ),
      );
      _showToast("No responsive servers found. Check your internet connection.");
      return null;
    }
  }

  // Start background testing to find better servers
  void _startBackgroundTesting(VpnConfigWithMetrics? currentConfig) async {
    if (currentConfig == null) return;

    // Schedule background testing after a short delay
    _backgroundTestTimer?.cancel();
    _backgroundTestTimer = Timer(const Duration(seconds: 2), () async {
      for (final config in _configManager.allConfigs) {
        if (config.id != currentConfig.id) {
          try {
            // Test this config in the background
            // This would normally use the latency service to test the connection
            // For now, we'll just check if it has a better ping
            if (config.currentPing > 0 &&
                currentConfig.currentPing > 0 &&
                (currentConfig.currentPing - config.currentPing) >= 40) {
              // Found a significantly better server
              setState(() {
                _fastestInBackground = config;
                _showFastestOverlay = true;
              });
              break; // Stop after finding the first better server
            }
          } catch (e) {
            continue; // Skip if test fails
          }
        }
      }
    });
  }

  // Refactored Main Button Action - Connect button now shows ads automatically during connection
  Future<void> _handleMainButtonAction() async {
    await _handleConnection();
  }

  // Toggle favorite status for the selected config
  Future<void> _toggleFavorite() async {
    final selectedConfig = _configManager.selectedConfig;

    if (selectedConfig != null) {
      await _configManager.toggleFavorite(selectedConfig.id);

      // Re-fetch the config to ensure we have the LATEST state after the toggle
      final updatedConfig = _configManager.getConfigById(selectedConfig.id);
      final isFavorite = updatedConfig?.isFavorite ?? false;
      final message = isFavorite ? "Added to Favorites" : "Removed from Favorites";

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isFavorite ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Show feedback that no server is selected
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("No server selected"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _showConnectionInfo() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Connection Logs", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
              itemCount: _connectionLogs.length,
              itemBuilder: (context, index) => Text(_connectionLogs[index], style: const TextStyle(color: Colors.grey, fontSize: 12)),
            )),
          ]
        )
      )
    );
  }

  Future<bool> _showAdDialog() async {
    bool adWatched = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future.delayed(const Duration(seconds: 3), () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
                adWatched = true;
              }
            });

            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text(
                'Advertisement',
                style: TextStyle(color: Colors.white),
              ),
              content: Container(
                width: double.maxFinite,
                height: 200,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.ad_units,
                      size: 64,
                      color: Colors.amber[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Advertisement',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Thank you for supporting our service',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Ad Content Placeholder',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return adWatched;
  }

  Future<void> _handleSessionExpiration() async {
    try {
      await _windowsVpnService.stopVpn();
      await _configManager.disconnectVpn(); 

      if (mounted) {
        _showToast('Session expired. Please reconnect.');
        _addLog('Session expired. Connection terminated.');
      }
    } catch (e) {
      AdvancedLogger.error('[HomeScreen] Session expiration handling failed: $e');
      if (mounted) {
        _showToast('Session expired but disconnect failed: $e');
      }
    }
  }

  Future<void> _openLogViewer() async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LogViewerScreen(),
      ),
    );
  }

  Future<void> _runSingleLatencyTest(VpnConfigWithMetrics config) async {
    try {
      if (mounted) {
        setState(() {
          _activeTestIds.add(config.id);
        });
      }
      
      _showToast('Testing latency for ${config.name}...');

      final result = await _latencyService.getAdvancedLatency(
        config.rawConfig,
        timeout: const Duration(seconds: 35),
        isPriority: true,
      );
      final latency = result.health.averageLatency;

      await _configManager.updateConfigMetrics(
        config.id,
        ping: latency,
        connectionSuccess: latency > 0,
      );

      _showToast('Latency test completed: ${latency}ms for ${config.name}');
    } catch (e) {
      _showToast('Latency test failed for ${config.name}: $e');
      AdvancedLogger.error('[HomeScreen] Latency test failed for ${config.name}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _activeTestIds.remove(config.id);
        });
      }
    }
  }

  Future<void> _runSingleSpeedTest(VpnConfigWithMetrics config) async {
    try {
      if (mounted) {
        setState(() {
          _activeTestIds.add(config.id);
        });
      }
      
      _showToast('Testing speed for ${config.name}...');

      final speed = await _latencyService.getDownloadSpeed(config.rawConfig);

      await _configManager.updateConfigMetrics(
        config.id,
        speed: speed,
        connectionSuccess: speed > 0,
      );

      _showToast('Speed test completed: ${speed.toStringAsFixed(2)}Mbps for ${config.name}');
    } catch (e) {
      _showToast('Speed test failed for ${config.name}: $e');
      AdvancedLogger.error('[HomeScreen] Speed test failed for ${config.name}: $e');
    } finally {
      if (mounted) {
        setState(() {
          _activeTestIds.remove(config.id);
        });
      }
    }
  }

  Future<void> _runSingleStabilityTest(VpnConfigWithMetrics config) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StabilityChartScreen(rawConfig: config.rawConfig),
      ),
    );
  }

  Future<void> _refreshConfigsFromGitHub() async {
    if (!mounted) return;

    _showToast('Refreshing configs from GitHub...');

    try {
      final stats = await _configManager.downloadConfigsFromGitHub();
      final added = stats['added'] ?? 0;
      final skipped = stats['skipped'] ?? 0;
      final total = stats['total'] ?? 0;

      if (added > 0) {
        _showToast("✅ Updated! Added $added new servers.");
      } else if (skipped > 0) {
        _showToast("ℹ️ No new servers found (Skipped $skipped duplicates).");
      } else {
        _showToast("⚠️ Check internet or source link.");
      }
    } catch (e) {
      _showToast('Failed to refresh configs: $e');
      AdvancedLogger.error('[HomeScreen] Failed to refresh configs: $e');
    }
  }

  Future<void> _runBackgroundFastestSearch() async {
    await Future.delayed(const Duration(seconds: 10));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('A faster route was found', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    final access = AccessManager();
    final remaining = access.remainingTime;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    
    final timeString = access.hasAccess 
        ? '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m'
        : 'Expired';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1E1E1E), const Color(0xFF252525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.timer, color: Colors.amber, size: 24),
          ),
          const SizedBox(width: 16),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Time Remaining",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  timeString,
                  style: TextStyle(
                    color: access.hasAccess ? Colors.white : Colors.redAccent,
                    fontSize: 20, 
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace'
                  ),
                ),
              ],
            ),
          ),
          
          ElevatedButton.icon(
            onPressed: _showAdSequence,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text("Add Time"),
          ),
        ],
      ),
    );
  }
}