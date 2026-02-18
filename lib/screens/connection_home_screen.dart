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
import '../services/funnel_service.dart'; // NEW: Funnel Service
import '../services/testers/ephemeral_tester.dart'; // NEW: Ephemeral Tester
import '../services/update_service.dart'; // NEW: Update Service
import '../utils/connectivity_utils.dart';

// Top-level function for sorting in background isolate
List<VpnConfigWithMetrics> _sortConfigs(List<VpnConfigWithMetrics> configs) {
  final sorted = List<VpnConfigWithMetrics>.from(configs);
  sorted.sort((a, b) => a.compareTo(b));
  return sorted;
}

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

        // NEW: Retry Config Fetch on Connect (Anti-Censorship)
        if (status == 'CONNECTED') {
           AdvancedLogger.info("[HomeScreen] VPN Connected. Retrying config fetch...");
           _configManager.fetchStartupConfigs();
           // Note: AdManagerService has its own listener for retrying ads.
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

      // ADD THIS DELAY: Cool-down period to allow OS to release TUN interface
      AdvancedLogger.info('Waiting for port release...');
      await Future.delayed(const Duration(seconds: 1)); // Cool-down period

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

      // Step 2: Show Ad via Unified Ad Manager
      final bool adSuccess = await AdManagerService().showPreConnectionAd(context);

      if (!adSuccess) return; // If ad failed or user didn't complete properly
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

    // 1. Fire & Forget Services (Parallel Startup)
    // AdManagerService initialized in initState
    UpdateService.checkAndShowUpdateDialog(context);

    setState(() {});

    // 2. Pre-flight Connectivity Check
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
       return; // Stop here. Do not load configs or start funnel.
    }

    // 3. Load Configs & Start Funnel (Only if Internet OK)
    // fetchStartupConfigs now uses compute() internally to prevent UI freeze
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
              // 1. Top Ad Banner
              SliverToBoxAdapter(
                child: _buildAdBannerSection(),
              ),

              // 2. Main Content Header (App Info, Connection Status, Controls)
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

              // 3. Middle Ad Banner (Bottom Slot)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    height: 250,
                    child: UniversalAdWidget(slot: 'home_banner_bottom', height: 250),
                  ),
                ),
              ),

              // 4. Progress Bar & Fastest Overlay
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

                      // "Switch to Faster" Overlay
                      if (_showFastestOverlay && _fastestInBackground != null)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
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
                    ],
                  ),
                ),
              ),

              // 5. Config List Header (Title + Actions)
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
                        icon: const Icon(Icons.delete_sweep, color: Colors.redAccent), // NEW: Use delete_sweep icon
                        onPressed: _showSmartCleanupDialog, // NEW: Call Smart Cleanup Dialog
                        tooltip: 'Cleanup Configs',
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),

              // 6. Sticky Tab Bar
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

              // 7. The Config List
              ListenableBuilder(
                listenable: _configManager,
                builder: (context, _) {
                  // Determine which list to show
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
                              const SizedBox(height: 8),
                              Text(
                                'Use Smart Paste to add configs',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 14,
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
                          onTestSpeed: () => _runSingleTest(config), // Replaced with Ephemeral Test
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

              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Methods ---

  // NEW: Smart Cleanup Dialog
  Future<void> _showSmartCleanupDialog() async {
    // Calculate counts for preview
    // Failed TCP: attempted (failureCount > 0) AND (funnelStage == 0 i.e. didn't pass TCP)
    final failedTcpCount = _configManager.allConfigs.where((c) => c.funnelStage == 0 && c.failureCount > 0).length;
    // Dead: Real Ping is -1
    final deadCount = _configManager.allConfigs.where((c) => c.currentPing == -1).length;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Smart Cleanup', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select cleanup criteria:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            _buildCleanupOption(
              context: context,
              title: "Remove Failed TCP",
              subtitle: "Deletes configs that failed handshake ($failedTcpCount items)",
              icon: Icons.network_locked,
              color: Colors.orangeAccent,
              onTap: () async {
                Navigator.pop(context);
                final removed = await _configManager.removeConfigs(failedTcp: true);
                _showToast("Removed $removed configs");
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            _buildCleanupOption(
              context: context,
              title: "Remove All Dead",
              subtitle: "Deletes all configs with -1 ping ($deadCount items)",
              icon: Icons.delete_forever,
              color: Colors.redAccent,
              onTap: () async {
                Navigator.pop(context);
                final removed = await _configManager.removeConfigs(dead: true);
                _showToast("Removed $removed configs");
                setState(() {});
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildCleanupOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
             Icon(icon, color: color, size: 28),
             const SizedBox(width: 16),
             Expanded(
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text(
                     title,
                     style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
                   ),
                   const SizedBox(height: 4),
                   Text(
                     subtitle,
                     style: TextStyle(color: Colors.grey[400], fontSize: 12),
                   ),
                 ],
               ),
             ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAllConfirmationDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Confirm Delete All', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure? This will clear all configs.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _configManager.clearAllData();
      setState(() {});
    }
  }

  Future<bool> _showDeleteConfirmationDialog(VpnConfigWithMetrics config) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Delete Config?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to remove "${config.name}"?',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    ) ?? false;
  }

  Widget _buildAdBannerSection() {
    return const SizedBox(
      height: 100, // Adjusted height for Top Banner
      width: double.infinity,
      child: UniversalAdWidget(slot: 'home_banner_top', height: 100),
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
                // Main Connect/Disconnect Button with State-Based Styling
                AnimatedBuilder(
                  animation: _configManager,
                  builder: (context, child) {
                    Color buttonColor;
                    IconData iconData;
                    String tooltipText;

                    if (_configManager.isConnected) {
                      buttonColor = Colors.greenAccent;
                      iconData = Icons.shield;
                      tooltipText = 'Connected - Protected';
                    } else if (_configManager.connectionStatus == 'Connecting...') {
                      buttonColor = Colors.yellow;
                      iconData = Icons.autorenew;
                      tooltipText = 'Connecting - Securing...';
                    } else {
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
                            size: 60,
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
          const SizedBox(height: 25),
          // Secondary Actions Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Fastest Button
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
              // Next Server Button
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.indigoAccent,
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
                  icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 22),
                  tooltip: 'Skip to Next Server',
                  onPressed: _handleNextServer,
                ),
              ),
              // Favorite Button
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
              // Auto-Switch Toggle Button
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
                      ? 'Auto-Switch Enabled'
                      : 'Auto-Switch Disabled',
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
        // Manual override: Disable blacklist check
        final importedCount = await _configManager.addConfigs(configs, checkBlacklist: false);

        if (importedCount > 0) {
          _showToast('$importedCount servers added successfully');
          setState(() {});
          await _configManager.refreshAllConfigs();
        } else {
          _showToast('No valid configs found in clipboard content');
        }
      } else {
         _showToast('No valid configs found in clipboard content');
      }
    } catch (e) {
      _showToast('Error processing clipboard: $e');
      AdvancedLogger.error('[HomeScreen] Smart Paste Error: $e');
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

  void _toggleAutoTestOnStartup(bool value) {
    setState(() {
      _autoTestOnStartup = value;
    });
  }

  // NEW: Run the advanced funnel test
  Future<void> _runFunnelTest() async {
    if (_configManager.allConfigs.isEmpty) return;
    await _funnelService.startFunnel();
  }

  // Find the fastest server using Funnel Test
  Future<void> _findFastestServer() async {
    if (_configManager.allConfigs.isEmpty) {
      _showToast("No configurations available. Please refresh.");
      return;
    }

    _showToast("Running Smart Funnel Test...");
    await _funnelService.startFunnel();
  }

  // Connect to the selected server (or find fastest if none selected)
  Future<void> _handleConnection() async {
    AdvancedLogger.info('[ConnectionHomeScreen] _handleConnection called');

    final homeProvider = Provider.of<HomeProvider>(context, listen: false);

    if (homeProvider.isConnected || homeProvider.connectionStatus == ConnectionStatus.connecting) {
      _isConnectionCancelled = true;
      await _configManager.stopAllOperations();
    } else {
      _isConnectionCancelled = false;
      // Check admin privileges (Windows)
      if (Platform.isWindows) {
        if (!await _nativeVpnService.isAdmin()) {
           _showToast("Administrator privileges required.");
           return;
        }
      }

      // Set connection status to connecting
      _configManager.setConnected(false, status: 'Connecting...');

      // Show ad automatically
      final access = AccessManager();
      if (!access.hasAccess) {
        await _showAdSequence();
        if (!access.hasAccess) return;
      }

      if (_configManager.allConfigs.isEmpty) {
        _showToast("No configurations available. Please refresh.");
        return;
      }

      var targetConfig = _configManager.selectedConfig;

      // If no server selected, find fastest
      if (targetConfig == null) {
        targetConfig = await _findFastestServerEager();
      }

      if (targetConfig == null) {
        _showToast("Failed to find a suitable server.");
        return;
      }

      // Attempt to connect with auto-failover
      await _connectWithFailover(targetConfig);
    }
  }

  /// Connect to a server with automatic failover to the next best server
  Future<void> _connectWithFailover(VpnConfigWithMetrics? initialConfig) async {
    if (initialConfig == null) return;

    VpnConfigWithMetrics currentConfig = initialConfig;
    int attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      if (_isConnectionCancelled || _configManager.isGlobalStopRequested) return;

      try {
        // 1. Pre-flight Check (Using EphemeralTester for accuracy)
        setState(() {
          _configManager.setConnected(false, status: 'Testing ${currentConfig.name}...');
        });

        // Use EphemeralTester to check if it's REALLY alive (not ghost)
        final testResult = await _ephemeralTester.runTest(currentConfig, mode: TestMode.connectivity);
        await _configManager.updateConfigDirectly(testResult);

        // RACE CONDITION CHECK: Did user cancel?
        if (_isConnectionCancelled || _configManager.isGlobalStopRequested) {
           return;
        }

        // Strict Check: Must pass Stage 2 (HTTP) or have valid ping
        if (testResult.funnelStage < 2 || testResult.currentPing == -1) {
             throw Exception("Pre-flight check failed (Ghost/Dead - Ping: ${testResult.currentPing})");
        }

        // 2. Connect
        setState(() {
          _configManager.setConnected(false, status: 'Connecting to ${currentConfig.name} (Attempt ${attempts + 1}/$maxAttempts)...');
        });

        await _nativeVpnService.connect(currentConfig.rawConfig);

        _configManager.updateConfigMetrics(
          currentConfig.id,
          connectionSuccess: true,
        );

        await _configManager.markSuccess(currentConfig.id);
        return;

      } catch (e, stackTrace) {
        AdvancedLogger.error('[ConnectionHomeScreen] Connection failed: $e', error: e, stackTrace: stackTrace);
        await _configManager.markFailure(currentConfig.id);

        if (_isConnectionCancelled) return;

        attempts++;
        if (attempts >= maxAttempts) {
          _showToast('Connection failed after $maxAttempts attempts.');
          _configManager.setConnected(false, status: 'Connection failed');
          return;
        }

        // Find next best server
        final nextBest = await _configManager.getBestConfig();
        if (nextBest != null && nextBest.id != currentConfig.id) {
          _showToast('Connection to ${currentConfig.name} failed. Trying ${nextBest.name}...');
          currentConfig = nextBest;
        } else {
          // User-friendly error message
          String errorMsg = "Connection failed";
          final eStr = e.toString().toLowerCase();
          if (eStr.contains("socketexception") || eStr.contains("os error")) {
             errorMsg = "Server unreachable";
          } else if (eStr.contains("pre-flight")) {
             errorMsg = "Server is dead (Pre-check failed)";
          }

          _showToast(errorMsg);
          _configManager.setConnected(false, status: 'Connection failed');
          return;
        }
      }
    }
  }

  // Find the fastest server with EAGER START logic
  Future<VpnConfigWithMetrics?> _findFastestServerEager() async {
    if (_configManager.allConfigs.isEmpty) return null;

    _showToast("Finding fastest server...");

    // Offload sorting to background isolate
    final sortedConfigs = await compute(_sortConfigs, _configManager.allConfigs);

    // Pick top one
    if (sortedConfigs.isNotEmpty) {
      final best = sortedConfigs.first;
      _configManager.selectConfig(best);
      return best;
    }
    return null;
  }

  // Handle Next Server Logic (Cycles through current list)
  Future<void> _handleNextServer() async {
    // 1. Identify current list based on active tab
    List<VpnConfigWithMetrics> currentList;
    switch (_tabController.index) {
      case 1:
        currentList = _configManager.validatedConfigs;
        break;
      case 2:
        currentList = _configManager.favoriteConfigs;
        break;
      case 0:
      default:
        currentList = _configManager.allConfigs;
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

  // Toggle favorite status for the selected config
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LogViewerScreen(),
      ),
    );
  }

  Future<void> _runSingleTest(VpnConfigWithMetrics config) async {
    try {
      if (mounted) setState(() => _activeTestIds.add(config.id));

      _showToast('Testing ${config.name}...');

      // Use Ephemeral Tester for single test
      final result = await _ephemeralTester.runTest(config);
      await _configManager.updateConfigDirectly(result);

      String stageName;
      switch (result.funnelStage) {
        case 0: stageName = "Failed"; break;
        case 1: stageName = "TCP Connected"; break;
        case 2: stageName = "Deep Testing Verified"; break;
        case 3: stageName = "Speed Verified"; break;
        default: stageName = "Unknown Status";
      }
      _showToast('Test complete. Result: $stageName');
      
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

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _SliverTabBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height + 16;

  @override
  double get maxExtent => _tabBar.preferredSize.height + 16;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: _tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return true;
  }
}
