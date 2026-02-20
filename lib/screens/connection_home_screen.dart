import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Explicit import for compute
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import '../models/vpn_config_with_metrics.dart';
import '../providers/home_provider.dart';
import '../services/config_manager.dart';
import '../services/native_vpn_service.dart';
import '../widgets/universal_ad_widget.dart';
import '../widgets/config_card.dart';
import '../utils/advanced_logger.dart';
import '../utils/clipboard_utils.dart';
import '../services/config_importer.dart';
import 'log_viewer_screen.dart';
import '../services/access_manager.dart';
import '../services/ad_manager_service.dart';
import '../services/funnel_service.dart';
import '../services/testers/ephemeral_tester.dart';
import '../services/update_service.dart';
import '../utils/connectivity_utils.dart';
import 'settings_screen.dart';

class ConnectionHomeScreen extends StatefulWidget {
  const ConnectionHomeScreen({super.key});

  @override
  State<ConnectionHomeScreen> createState() => _ConnectionHomeScreenState();
}

class _ConnectionHomeScreenState extends State<ConnectionHomeScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // 1. Initialize services IMMEDIATELY
  final NativeVpnService _nativeVpnService = NativeVpnService();
  final FunnelService _funnelService = FunnelService();
  final EphemeralTester _ephemeralTester = EphemeralTester();

  // 2. State Variables
  final ConfigManager _configManager = ConfigManager();
  bool _isInitialized = false;
  bool _autoTestOnStartup = true;
  bool _isWatchingAd = false;
  final List<String> _connectionLogs = [];
  Timer? _timerUpdater;
  final Set<String> _activeTestIds = {};

  // Connection Control
  bool _isConnectionCancelled = false;

  // Parallel Intelligence Variables
  VpnConfigWithMetrics? _fastestInBackground;
  bool _showFastestOverlay = false;
  Timer? _backgroundTestTimer;

  // Auto-switch Variables
  int _highPingCounter = 0;
  static const int _consecutiveHighPingCount = 2; // consecutive checks before switching
  Timer? _pingMonitorTimer;

  // Progress State
  String _testProgress = "";

  late TabController _tabController;

  @override
  void initState() {
    super.initState();

    // 1. Initialize Ad Service IMMEDIATELY
    AdManagerService().initialize();

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {}); // Rebuild to switch lists
      }
    });

    _initialize();
    WidgetsBinding.instance.addObserver(this);

    // AccessManager Listener
    AccessManager().init().then((_) {
      if (mounted) setState(() {});
    });
    AccessManager().addListener(_onTimeChanged);

    // Register Stop Callback
    _configManager.stopVpnCallback = _nativeVpnService.disconnect;

    // Auto-Switch Callback
    _configManager.onAutoSwitch = (config) {
      if (mounted) {
         AdvancedLogger.info("[HomeScreen] Auto-Switch triggered to: ${config.name}");
         _handleConnection();
      }
    };

    // Listen to Funnel Progress
    _funnelService.progressStream.listen((msg) {
       if (mounted) setState(() => _testProgress = msg);
    });

    // VPN Connection Status Listener
    _nativeVpnService.connectionStatusStream.listen((status) {
      AdvancedLogger.info('[ConnectionHomeScreen] Received VPN status update: $status');
      if (mounted) {
        setState(() {
          // Update the connection status in ConfigManager to reflect the actual VPN status
          _configManager.setConnected(status == 'CONNECTED', status: _getConnectionStatusMessage(status));
        });

        // NEW: Post-Connect Logic (Anti-Censorship)
        if (status == 'CONNECTED') {
           AdvancedLogger.info("[HomeScreen] VPN Connected. Retrying config fetch...");
           _configManager.fetchStartupConfigs();

           // Trigger Updates & Ads with Delay
           Future.delayed(const Duration(seconds: 3), () {
             if (mounted) {
               AdvancedLogger.info("[HomeScreen] Triggering Post-Connect Update & Ad Check...");
               UpdateService.checkForUpdatesSilently(context);
               AdManagerService().fetchLatestAds();
             }
           });
        }
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
    _tabController.dispose();
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
      _highPingCounter = 0;
      return;
    }

    if (!_configManager.isConnected) {
      _highPingCounter = 0;
      return;
    }

    // Check if current ping is high
    // Increased threshold to 3000ms to prevent loop
    if (_configManager.selectedConfig != null && _configManager.selectedConfig!.currentPing > 3000) {
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
      await _nativeVpnService.disconnect();

      // Cool-down period to allow OS to release TUN interface
      AdvancedLogger.info('Waiting for port release...');
      await Future.delayed(const Duration(seconds: 1));

      // Find the fastest server
      final newConfig = await _findFastestServerEager();
      if (newConfig != null) {
        _configManager.selectConfig(newConfig);
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
      case 'CONNECTED': return 'Connected';
      case 'CONNECTING': return 'Connecting...';
      case 'DISCONNECTED': return 'Disconnected';
      case 'ERROR': return 'Connection Error';
      default: return status;
    }
  }

  Color _getPingColor(int ping) {
    if (ping < 0) return Colors.grey;
    if (ping < 150) return Colors.green.shade700;
    if (ping < 400) return Colors.yellow.shade700;
    return Colors.red.shade700;
  }
  
  // --- AD REWARD LOGIC ---
  Future<void> _showAdSequence() async {
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
      final bool adSuccess = await AdManagerService().showPreConnectionAd(context);
      if (!adSuccess) return;
      if (!mounted) return;

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
    final bool hasInternet = await ConnectivityUtils.hasInternet();

    if (!hasInternet) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(
             content: Text("No Internet Connection. Testing Aborted."),
             backgroundColor: Colors.redAccent,
             duration: Duration(seconds: 4),
           ),
         );
       }
       return;
    }

    _configManager.fetchStartupConfigs().then((hasNewConfigs) {
       if (hasNewConfigs && _autoTestOnStartup && !_configManager.isConnected && mounted) {
           AdvancedLogger.info("[HomeScreen] Startup configs loaded. Triggering Auto-Test...");
           _runFunnelTest();
       }
    });
  }

  Future<void> _runSmartAutoTest() async {
    if (!mounted) return;
    if (_configManager.allConfigs.isEmpty) {
       _showToast("No configs available to test");
       return;
    }
    AdvancedLogger.info("🚀 [Auto-Test] Running Smart Auto-Test (Funnel)...");
    await _runFunnelTest();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
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
        child: RefreshIndicator(
          backgroundColor: const Color(0xFF1A1A1A),
          color: Colors.blueAccent,
          onRefresh: _refreshConfigsFromGitHub,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildAdBannerSection()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
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
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    height: 250,
                    child: UniversalAdWidget(slot: 'home_banner_bottom', height: 250),
                  ),
                ),
              ),
              // Progress Bar & Overlay
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: Column(
                    children: [
                       if (_testProgress.isNotEmpty && _testProgress != "Completed" && _testProgress != "Stopped")
                          Container(
                             padding: const EdgeInsets.all(12),
                             decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blueAccent.withOpacity(0.3))
                             ),
                             child: Row(
                                children: [
                                   const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2)
                                   ),
                                   const SizedBox(width: 12),
                                   Expanded(child: Text(_testProgress, style: const TextStyle(color: Colors.white, fontSize: 13))),
                                   IconButton(
                                      icon: const Icon(Icons.stop, color: Colors.redAccent),
                                      onPressed: () {
                                         _funnelService.stop();
                                         _showToast("Test Stopped");
                                      },
                                   )
                                ],
                             ),
                          ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.list, color: Colors.blueAccent, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'Server Configuration',
                        style: TextStyle(
                          color: Colors.grey[100],
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.speed, color: Colors.blueAccent),
                        onPressed: _runSmartAutoTest,
                        tooltip: 'Test All Connections (Funnel)',
                        splashRadius: 20,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                        onPressed: _showSmartCleanupDialog,
                        tooltip: 'Cleanup Configs',
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [
                          Colors.blueAccent.withOpacity(0.8),
                          Colors.indigoAccent.withOpacity(0.8),
                        ],
                      ),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey[400],
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 12,
                    ),
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.list, size: 18),
                        text: 'All (${_configManager.allConfigs.length})',
                      ),
                      Tab(
                        icon: const Icon(Icons.check_circle, size: 18),
                        text: 'Valid (${_configManager.validatedConfigs.length})',
                      ),
                      Tab(
                        icon: const Icon(Icons.star, size: 18),
                        text: 'Favs (${_configManager.favoriteConfigs.length})',
                      ),
                    ],
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: _configManager,
                builder: (context, _) {
                  List<VpnConfigWithMetrics> configs;
                  switch (_tabController.index) {
                    case 1:
                      configs = _configManager.validatedConfigs;
                      break;
                    case 2:
                      configs = _configManager.favoriteConfigs;
                      break;
                    case 0:
                    default:
                      configs = _configManager.allConfigs;
                  }

                  if (configs.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.all(50),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 64,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No configs available',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final config = configs[index];
                        return ConfigCard(
                          config: config,
                          isSelected: _configManager.selectedConfig?.id == config.id,
                          isTesting: _activeTestIds.contains(config.id),
                          onTap: () {
                            _configManager.selectConfig(config);
                            setState(() {});
                          },
                          onTestLatency: () => _runSingleTest(config),
                          onTestSpeed: () => _runSingleTest(config),
                          onToggleFavorite: () async {
                             await _configManager.toggleFavorite(config.id);
                             setState(() {});
                          },
                          onDelete: () async {
                            final confirm = await _showDeleteConfirmationDialog(config);
                            if (confirm && mounted) {
                              await _configManager.deleteConfig(config.id);
                              setState(() {});
                            }
                          },
                        );
                      },
                      childCount: configs.length,
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ),
        ),
      ),
    );
  }

  // --- LOGIC METHODS ---

  Future<void> _handleConnection() async {
    final homeProvider = Provider.of<HomeProvider>(context, listen: false);

    if (homeProvider.isConnected || homeProvider.connectionStatus == ConnectionStatus.connecting) {
      _isConnectionCancelled = true;
      await _configManager.stopAllOperations();
      return;
    }

    _isConnectionCancelled = false;
    // Admin Check
    if (Platform.isWindows && !await _nativeVpnService.isAdmin()) {
       _showToast("Administrator privileges required.");
       return;
    }

    _configManager.setConnected(false, status: 'Connecting...');

    // Access Check
    final access = AccessManager();
    if (!access.hasAccess) {
      await _showAdSequence();
      if (!access.hasAccess) return;
    }

    if (_configManager.allConfigs.isEmpty) {
      _showToast("No configurations available. Please refresh.");
      return;
    }

    // 1. SMART WAIT LOOP
    // If we have no valid configs yet, wait for the Funnel
    if (_configManager.validatedConfigs.isEmpty) {
        setState(() => _configManager.setConnected(false, status: 'Testing servers...'));

        // Start Funnel if not running
        _funnelService.startFunnel(retestDead: false); // Prioritize fresh ones

        int waits = 0;
        while (_configManager.validatedConfigs.isEmpty && waits < 15 && !_isConnectionCancelled) {
             await Future.delayed(const Duration(seconds: 1));
             waits++;
        }

        if (_isConnectionCancelled) return;

        if (_configManager.validatedConfigs.isEmpty) {
            _showToast("No accessible servers found. Please update list.");
            _configManager.setConnected(false, status: 'Failed');
            return;
        }
    }

    // 2. Auto-Select Best
    // Validated list is already sorted by Best (Speed > Ping)
    final bestConfig = _configManager.validatedConfigs.first;
    _configManager.selectConfig(bestConfig);

    // 3. Connect with Failover
    await _connectWithFailover(bestConfig);
  }

  Future<void> _connectWithFailover(VpnConfigWithMetrics? initialConfig) async {
    if (initialConfig == null) return;

    VpnConfigWithMetrics currentConfig = initialConfig;
    int attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      if (_isConnectionCancelled || _configManager.isGlobalStopRequested) return;

      try {
        setState(() {
          _configManager.setConnected(false, status: 'Testing ${currentConfig.name}...');
        });

        // 1. Pre-flight Check (Strict)
        // Ensure server didn't die in last few seconds
        // Use connectivity mode (Stage 2) as it's faster and sufficient for alive check
        final testResult = await _ephemeralTester.runTest(currentConfig, mode: TestMode.connectivity);

        if (testResult.funnelStage < 2 || testResult.currentPing == -1) {
             // Mark as failed and throw to trigger failover
             await _configManager.markFailure(currentConfig.id);
             throw Exception("Pre-flight check failed (Ghost/Dead)");
        }

        // Update with latest metrics
        await _configManager.updateConfigDirectly(testResult);

        if (_isConnectionCancelled) return;

        // 2. Connect
        setState(() {
          _configManager.setConnected(false, status: 'Connecting to ${currentConfig.name}...');
        });

        await _nativeVpnService.connect(currentConfig.rawConfig);

        _configManager.updateConfigMetrics(
          currentConfig.id,
          connectionSuccess: true,
        );

        await _configManager.markSuccess(currentConfig.id);
        return; // Success!

      } catch (e) {
        AdvancedLogger.error('Connection Attempt ${attempts+1} Failed: $e');

        // Mark failed
        await _configManager.markFailure(currentConfig.id);

        if (_isConnectionCancelled) return;

        attempts++;
        if (attempts >= maxAttempts) {
           _showToast("Connection failed after $maxAttempts attempts.");
           _configManager.setConnected(false, status: 'Connection failed');
           return;
        }

        // Pick next best
        // getBestConfig() returns valid.first, which might be the one we just failed
        // (if markFailure didn't push it down list fast enough or if it's the only one).
        // markFailure increases failureCount, which reduces score, so it should move down.
        // We wait a tiny bit for sort to propagate? ConfigManager handles it synchronously in markFailure.

        final nextBest = await _configManager.getBestConfig();

        if (nextBest != null && nextBest.id != currentConfig.id) {
           _showToast("Server unreachable. Switching to ${nextBest.name}...");
           currentConfig = nextBest;
           _configManager.selectConfig(nextBest);
        } else {
           // No other good servers
           _showToast("No other working servers available.");
           _configManager.setConnected(false, status: 'Connection failed');
           return;
        }
      }
    }
  }

  Future<VpnConfigWithMetrics?> _findFastestServerEager() async {
    // Just return best config as Manager already sorts it
    return _configManager.getBestConfig();
  }

  // ... (Rest of existing methods: _handleNextServer, _handleMainButtonAction, etc. kept as is) ...
  // Re-pasting standard methods for completeness of file context

  Future<void> _handleNextServer() async {
    List<VpnConfigWithMetrics> currentList;
    switch (_tabController.index) {
      case 1: currentList = _configManager.validatedConfigs; break;
      case 2: currentList = _configManager.favoriteConfigs; break;
      case 0: default: currentList = _configManager.allConfigs;
    }

    final nextConfig = _configManager.getNextConfig(currentList);
    if (nextConfig == null) {
      _showToast("No servers in current list to switch to.");
      return;
    }

    _configManager.selectConfig(nextConfig);
    _showToast("Switching to: ${nextConfig.name}");

    if (_configManager.isConnected || _configManager.connectionStatus == 'Connecting...') {
        _isConnectionCancelled = true;
        await _nativeVpnService.disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
        _isConnectionCancelled = false;
    }
    await _handleConnection();
  }

  Future<void> _handleMainButtonAction() async {
    await _handleConnection();
  }

  Future<void> _toggleFavorite() async {
    final selectedConfig = _configManager.selectedConfig;
    if (selectedConfig != null) {
      await _configManager.toggleFavorite(selectedConfig.id);
      setState(() {});
    } else {
      _showToast("No server selected");
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

  Future<void> _openLogViewer() async {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogViewerScreen()));
  }

  Future<void> _runSingleTest(VpnConfigWithMetrics config) async {
    try {
      if (mounted) setState(() => _activeTestIds.add(config.id));
      _showToast('Testing ${config.name}...');
      final result = await _ephemeralTester.runTest(config);
      await _configManager.updateConfigDirectly(result);
      _showToast('Test complete. Stage: ${result.funnelStage}');
    } catch (e) {
      _showToast('Test failed: $e');
    } finally {
      if (mounted) setState(() => _activeTestIds.remove(config.id));
    }
  }

  Future<void> _refreshConfigsFromGitHub() async {
    if (!mounted) return;
    _showToast('Refreshing configs from GitHub...');
    try {
      await _configManager.fetchStartupConfigs();
      _showToast('Refresh check completed');
    } catch (e) {
      _showToast('Failed to refresh configs: $e');
    }
  }

  // --- RESTORED UI METHODS ---

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _runFunnelTest() async {
    if (_configManager.allConfigs.isEmpty) return;
    _funnelService.startFunnel();
  }

  Widget _buildAdBannerSection() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: UniversalAdWidget(slot: 'home_banner_top'),
    );
  }

  Widget _buildAppHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'V2Ray',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
        )
      ],
    );
  }

  Widget _buildSubscriptionCard() {
    final access = AccessManager();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        leading: const Icon(Icons.workspace_premium, color: Colors.amber, size: 32),
        title: const Text('Free Plan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(
          access.hasAccess
              ? '${access.remainingTime.inHours}h ${access.remainingTime.inMinutes % 60}m remaining'
              : 'No active plan',
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: _showAdSequence,
          child: const Text('Add Time'),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    Color statusColor;
    if (_configManager.isConnected) {
      statusColor = Colors.greenAccent;
    } else if (_configManager.connectionStatus == 'Failed' || _configManager.connectionStatus.contains('Error')) {
      statusColor = Colors.redAccent;
    } else {
      statusColor = Colors.grey;
    }

    return Center(
      child: Text(
        _configManager.connectionStatus,
        style: TextStyle(
          color: statusColor,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildConnectButton() {
    final isConnected = _configManager.isConnected;
    final isConnecting = _configManager.connectionStatus.toLowerCase().contains('connecting');

    return Center(
      child: GestureDetector(
        onTap: _handleConnection,
        child: Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected
                ? Colors.redAccent
                : (isConnecting ? Colors.orange : Colors.green),
            boxShadow: [
              BoxShadow(
                color: (isConnected ? Colors.red : Colors.green).withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isConnected ? Icons.power_settings_new : Icons.power_settings_new,
                size: 60,
                color: Colors.white,
              ),
              const SizedBox(height: 10),
              Text(
                isConnected ? 'DISCONNECT' : (isConnecting ? 'CONNECTING' : 'CONNECT'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedConfig() {
    final config = _configManager.selectedConfig;
    if (config == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ConfigCard(
        config: config,
        isSelected: true,
        isTesting: _activeTestIds.contains(config.id),
        onTap: () {}, // Already selected
        onTestLatency: () => _runSingleTest(config),
        onTestSpeed: () => _runSingleTest(config),
        onToggleFavorite: () async {
           await _configManager.toggleFavorite(config.id);
           setState(() {});
        },
        onDelete: () async {
          final confirm = await _showDeleteConfirmationDialog(config);
          if (confirm && mounted) {
            await _configManager.deleteConfig(config.id);
            setState(() {});
          }
        },
      ),
    );
  }

  Widget _buildAutoTestToggle() {
    return SwitchListTile(
      title: const Text('Auto-Test on Startup', style: TextStyle(color: Colors.white)),
      value: _autoTestOnStartup,
      activeColor: Colors.blueAccent,
      onChanged: (val) {
        setState(() {
          _autoTestOnStartup = val;
        });
      },
    );
  }

  void _showSmartCleanupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Smart Cleanup', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Remove failed and dead configs?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final removed = await _configManager.removeConfigs(failedTcp: true, dead: true);
              _showToast("Removed $removed configs");
            },
            child: const Text('Cleanup', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<bool> _showDeleteConfirmationDialog(VpnConfigWithMetrics config) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Config', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete ${config.name}?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    ) ?? false;
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _SliverTabBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;

  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF121212), // Match Scaffold bg
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}
