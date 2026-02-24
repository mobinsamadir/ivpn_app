import 'package:flutter/material.dart';
// Explicit import for compute
import 'dart:async';
import 'dart:io';
import '../models/vpn_config_with_metrics.dart';
import '../services/config_manager.dart';
import '../services/native_vpn_service.dart';
import '../widgets/universal_ad_widget.dart';
import '../widgets/config_card.dart';
import '../utils/advanced_logger.dart';
import '../services/access_manager.dart';
import '../services/ad_manager_service.dart';
import '../services/funnel_service.dart';
import '../services/testers/ephemeral_tester.dart';
import '../services/config_gist_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/ad_explanation_dialog.dart';
import 'settings_screen.dart';

class ConnectionHomeScreen extends StatefulWidget {
  final NativeVpnService? nativeVpnService;
  final FunnelService? funnelService;
  final EphemeralTester? ephemeralTester;
  final ConfigManager? configManager;
  final AdManagerService? adManagerService;
  final AccessManager? accessManager;
  final ConnectivityService? connectivityService;
  final ConfigGistService? configGistService;

  const ConnectionHomeScreen({
    super.key,
    this.nativeVpnService,
    this.funnelService,
    this.ephemeralTester,
    this.configManager,
    this.adManagerService,
    this.accessManager,
    this.connectivityService,
    this.configGistService,
  });

  @override
  State<ConnectionHomeScreen> createState() => _ConnectionHomeScreenState();
}

class _ConnectionHomeScreenState extends State<ConnectionHomeScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // 1. Services
  late final NativeVpnService _nativeVpnService;
  late final FunnelService _funnelService;
  late final EphemeralTester _ephemeralTester;
  late final ConfigManager _configManager;
  late final AdManagerService _adManagerService;
  late final AccessManager _accessManager;
  late final ConnectivityService _connectivityService;
  late final ConfigGistService _configGistService;

  // 2. State Variables
  bool _isInitialized = false;
  bool _autoTestOnStartup = true;
  Timer? _timerUpdater;
  final Set<String> _activeTestIds = {};

  // Connection Control
  bool _isConnectionCancelled = false;
  // CRITICAL FIX: Debounce Auto-Switch
  bool _isSwitching = false;
  String _lastNativeStatus = "DISCONNECTED";

  // Auto-switch Variables
  int _highPingCounter = 0;
  static const int _consecutiveHighPingCount = 2; // consecutive checks before switching
  Timer? _pingMonitorTimer;

  // Progress State
  String _testProgress = "";

  // Stream Subscriptions
  StreamSubscription? _funnelSubscription;
  StreamSubscription? _vpnStatusSubscription;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();

    _nativeVpnService = widget.nativeVpnService ?? NativeVpnService();
    _funnelService = widget.funnelService ?? FunnelService();
    _ephemeralTester = widget.ephemeralTester ?? EphemeralTester();
    _configManager = widget.configManager ?? ConfigManager();
    _adManagerService = widget.adManagerService ?? AdManagerService();
    _accessManager = widget.accessManager ?? AccessManager();
    _connectivityService = widget.connectivityService ?? ConnectivityService();
    _configGistService = widget.configGistService ?? ConfigGistService();

    // 1. Initialize Ad Service IMMEDIATELY
    _adManagerService.initialize();

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {}); // Rebuild to switch lists
      }
    });

    _initialize();
    WidgetsBinding.instance.addObserver(this);

    // AccessManager Listener
    _accessManager.init().then((_) {
      if (mounted) setState(() {});
    });
    _accessManager.addListener(_onTimeChanged);

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
    _funnelSubscription = _funnelService.progressStream.listen((msg) {
       if (mounted) setState(() => _testProgress = msg);
    });

    // VPN Connection Status Listener
    _vpnStatusSubscription = _nativeVpnService.connectionStatusStream.listen((status) {
      AdvancedLogger.info('[ConnectionHomeScreen] Received VPN status update: $status');
      if (mounted) {
        setState(() {
          _lastNativeStatus = status;
          // Update the connection status in ConfigManager to reflect the actual VPN status
          _configManager.setConnected(status == 'CONNECTED', status: _getConnectionStatusMessage(status));
        });

        // NEW: Post-Connect Logic (Anti-Censorship)
        if (status == 'CONNECTED') {
           AdvancedLogger.info("[HomeScreen] VPN Connected. Retrying config fetch...");
           // _configManager.fetchStartupConfigs(); // Disabled autonomous config fetch

           // Trigger Updates & Ads with Delay
           Future.delayed(const Duration(seconds: 3), () {
             if (mounted) {
               AdvancedLogger.info("[HomeScreen] Triggering Post-Connect Ad Check...");
               _adManagerService.fetchLatestAds();
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
    _funnelSubscription?.cancel();
    _vpnStatusSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _accessManager.removeListener(_onTimeChanged);
    _timerUpdater?.cancel();
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

    // CRITICAL FIX: Only check ping if we are TRULY connected reported by Native OS
    if (_lastNativeStatus != "CONNECTED") {
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
    // CRITICAL FIX: Prevent concurrent switching (Infinite Loop Protection)
    if (_isSwitching) {
      AdvancedLogger.warn('[AutoSwitch] Already switching. Ignored.');
      return;
    }

    _isSwitching = true;
    AdvancedLogger.info('[ConnectionHomeScreen] Initiating auto-switch due to high ping');
    _showToast("High ping detected. Switching to best server...");

    try {
      // Stop current VPN connection
      await _nativeVpnService.disconnect();

      // Cool-down period to allow OS to release TUN interface
      AdvancedLogger.info('Waiting for port release...');
      await Future.delayed(const Duration(seconds: 2)); // Increased delay for safety

      // Use Smart Failover
      await _configManager.connectWithSmartFailover();

    } catch (e, stackTrace) {
      AdvancedLogger.error('[ConnectionHomeScreen] Auto-switch failed: $e', error: e, stackTrace: stackTrace);
      _showToast("Auto-switch failed: $e");
    } finally {
      _isSwitching = false;
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

  // --- AD REWARD LOGIC ---
  Future<void> _showAdSequence() async {
    final adSuccess = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AdExplanationDialog(
        onAdView: () async {
          // This callback is executed when user clicks "View Ad"
          return await _adManagerService.showPreConnectionAd(context);
        },
      ),
    );

    if (adSuccess == true) {
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
        await _accessManager.addTime(const Duration(hours: 1));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Success! +1 Hour Added."),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } else if (adSuccess == false) {
      // Handle Ad Failure / Cancelled
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Ad failed to load. Please try again."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _initAppSequence() async {
    if (!mounted) return;
    setState(() {});
    final bool hasInternet = await _connectivityService.hasInternet();

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

    // New Smart Fetch Logic
    try {
      await _configGistService.fetchAndApplyConfigs(_configManager);
    } catch (e) {
      AdvancedLogger.warn("[HomeScreen] Config fetch failed: $e");
    }

    // Auto Test if configs exist
    if (_configManager.allConfigs.isNotEmpty && _autoTestOnStartup && !_configManager.isConnected && mounted) {
        AdvancedLogger.info("[HomeScreen] Triggering Auto-Test...");
        _runFunnelTest();
    }
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
          onRefresh: _refreshConfigsManual,
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
                      ListenableBuilder(
                        listenable: _configManager,
                        builder: (context, _) => Column(
                          children: [
                            _buildConnectionStatus(),
                            const SizedBox(height: 12),
                            _buildConnectButton(),
                          ],
                        ),
                      ),
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
                                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3))
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
                        icon: const Icon(Icons.refresh, color: Colors.greenAccent),
                        onPressed: _refreshConfigsManual,
                        tooltip: 'Force Refresh',
                        splashRadius: 20,
                      ),
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
                          Colors.blueAccent.withValues(alpha: 0.8),
                          Colors.indigoAccent.withValues(alpha: 0.8),
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
    if (_configManager.isConnected || _configManager.connectionStatus.toLowerCase().contains('connecting')) {
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
    final access = _accessManager;
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

    // 2. Delegate to Service (Smart Failover)
    await _configManager.connectWithSmartFailover();
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

  Future<void> _refreshConfigsManual() async {
    if (!mounted) return;
    _showToast('Refreshing configs...');
    try {
      await _configGistService.fetchAndApplyConfigs(_configManager, force: true);
      _showToast('Refresh completed');
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
    final access = _accessManager;
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
                color: (isConnected ? Colors.red : Colors.green).withValues(alpha: 0.4),
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
      activeThumbColor: Colors.blueAccent,
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
