import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Explicit import for compute
import 'dart:async';
import 'dart:io';
import '../models/vpn_config_with_metrics.dart';
import '../services/config_manager.dart';
import '../services/native_vpn_service.dart';
import '../widgets/universal_ad_widget.dart';
import '../widgets/config_card.dart';
import '../utils/advanced_logger.dart';
import '../services/time_wallet_service.dart';
import '../services/ad_manager_service.dart';
import '../services/funnel_service.dart';
import '../services/testers/ephemeral_tester.dart';
import '../services/config_gist_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/ad_explanation_dialog.dart';
import '../widgets/shimmer_config_card.dart';
import '../widgets/sliver_tab_bar_delegate.dart';
import '../widgets/scale_on_tap.dart';
import 'settings_screen.dart';
import 'log_viewer_screen.dart';

class ConnectionHomeScreen extends StatefulWidget {
  final NativeVpnService? nativeVpnService;
  final FunnelService? funnelService;
  final EphemeralTester? ephemeralTester;
  final ConfigManager? configManager;
  final AdManagerService? adManagerService;

  final ConnectivityService? connectivityService;
  final ConfigGistService? configGistService;

  const ConnectionHomeScreen({
    super.key,
    this.nativeVpnService,
    this.funnelService,
    this.ephemeralTester,
    this.configManager,
    this.adManagerService,
    this.connectivityService,
    this.configGistService,
  });

  @override
  State<ConnectionHomeScreen> createState() => _ConnectionHomeScreenState();
}

class _ConnectionHomeScreenState extends State<ConnectionHomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // 1. Services
  late final NativeVpnService _nativeVpnService;
  late final FunnelService _funnelService;
  late final EphemeralTester _ephemeralTester;
  late final ConfigManager _configManager;
  late final AdManagerService _adManagerService;
  final TimeWalletService _timeWalletService = TimeWalletService();
  late final ConnectivityService _connectivityService;
  late final ConfigGistService _configGistService;

  // 2. State Variables
  bool _isInitialized = false;
  bool _autoTestOnStartup = true;
  bool _autoRefreshOnStartup = true;
  bool _isFetching = false;
  Timer? _timerUpdater;
  final Set<String> _activeTestIds = {};

  // Connection Control
  // CRITICAL FIX: Debounce Auto-Switch
  bool _isSwitching = false;
  // Native Operation check
  bool get _isNativeOperationInProgress {
    final status = _configManager.connectionStatus.toLowerCase();
    return status.contains('disconnecting') ||
        status.contains('testing') ||
        _activeTestIds.isNotEmpty ||
        _isFetching ||
        _isSwitching;
  }

  String _lastNativeStatus = "DISCONNECTED";
  bool _isAdmin = true;

  // NEW: Auto-switch throttle and limits
  int _consecutiveFailures = 0;
  DateTime? _lastAutoSwitchAttempt;

  // Auto-switch Variables
  int _highPingCounter = 0;
  DateTime? _lastAutoSwitchTime;
  static const int _consecutiveHighPingCount =
      2; // consecutive checks before switching
  Timer? _pingMonitorTimer;

  // Progress State
  String _testProgress = "";

  // Stream Subscriptions
  StreamSubscription? _funnelSubscription;
  StreamSubscription? _vpnStatusSubscription;
  StreamSubscription? _statsSubscription;
  int _rxBytes = 0;
  int _txBytes = 0;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();

    _nativeVpnService = widget.nativeVpnService ?? NativeVpnService();
    _funnelService = widget.funnelService ?? FunnelService();
    _ephemeralTester = widget.ephemeralTester ?? EphemeralTester();
    _configManager = widget.configManager ?? ConfigManager();
    _adManagerService = widget.adManagerService ?? AdManagerService();

    _connectivityService = widget.connectivityService ?? ConnectivityService();
    _configGistService = widget.configGistService ?? ConfigGistService();

    // 1. Initialize Ad Service IMMEDIATELY
    _adManagerService.initialize();

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        // Rebuild handled by AnimatedBuilder
      }
    });

    _initialize();
    WidgetsBinding.instance.addObserver(this);

    // AccessManager Listener
    _timeWalletService.init().then((_) {
      if (mounted) setState(() {});
    });
    _timeWalletService.addListener(_onTimeChanged);

    // Register Stop Callback
    _configManager.stopVpnCallback = _nativeVpnService.disconnect;

    // Auto-Switch Callback
    _configManager.onAutoSwitch = (config) {
      if (mounted) {
        AdvancedLogger.info(
          "[HomeScreen] Auto-Switch triggered to: ${config.name}",
        );
        _handleConnection();
      }
    };

    // Listen to Funnel Progress
    _funnelSubscription = _funnelService.progressStream.listen((msg) {
      if (mounted) setState(() => _testProgress = msg);
    });

    // VPN Connection Status Listener
    _vpnStatusSubscription = _nativeVpnService.connectionStatusStream.listen((
      status,
    ) {
      AdvancedLogger.info(
        '[ConnectionHomeScreen] Received VPN status update: $status',
      );
      if (mounted) {
        setState(() {
          _lastNativeStatus = status;
          // Update the connection status in ConfigManager to reflect the actual VPN status
          _configManager.setConnected(
            status == 'CONNECTED',
            status: _getConnectionStatusMessage(status),
          );
        });

        if (status == 'DISCONNECTED' ||
            status.contains('Administrator privileges required') ||
            status.contains('Administrator')) {
          if (status.contains('Administrator privileges required') ||
              status.contains('Administrator')) {
            _isAdmin = false;
            _configManager.userInitiatedDisconnect =
                true; // Stop auto-switching
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('نیاز به دسترسی ادمین (Run as Administrator)'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }

          setState(() {
            _rxBytes = 0;
            _txBytes = 0;
          });
          if (!_configManager.userInitiatedDisconnect &&
              !_configManager.isConnectionCancelled) {
            final now = DateTime.now();
            if (_lastAutoSwitchAttempt != null &&
                now.difference(_lastAutoSwitchAttempt!).inSeconds < 3) {
              AdvancedLogger.warn("[HomeScreen] Auto-switch throttled.");
              return;
            }
            _lastAutoSwitchAttempt = now;
            _consecutiveFailures++;

            if (_consecutiveFailures > 5) {
              AdvancedLogger.warn(
                "[HomeScreen] Auto-switch stopped due to too many consecutive failures.",
              );
              _configManager.userInitiatedDisconnect = true;
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'اتصال مکرراً قطع شد. سوییچ خودکار متوقف شد.',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            } else {
              AdvancedLogger.warn(
                "[HomeScreen] Unexpected disconnect. Attempting auto-switch (Attempt $_consecutiveFailures)...",
              );
              final validConfigs = _configManager.validatedConfigs;
              if (validConfigs.isNotEmpty) {
                if (_configManager.selectedConfig != null) {
                  _configManager.setConnected(false, status: 'Failed');
                }

                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted && !_configManager.userInitiatedDisconnect) {
                    _skipServer();
                  }
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('هیچ کانفیگ معتبری یافت نشد')),
                );
              }
            }
          }
          _configManager.userInitiatedDisconnect = false;
          _configManager.isConnectionCancelled = false;
        }

        // NEW: Post-Connect Logic (Anti-Censorship)
        if (status == 'CONNECTED') {
          _consecutiveFailures = 0; // Reset on success

          AdvancedLogger.info(
            "[HomeScreen] VPN Connected. Retrying config fetch...",
          );
          // _configManager.fetchStartupConfigs(); // Disabled autonomous config fetch

          // Trigger Updates & Ads with Delay
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              AdvancedLogger.info(
                "[HomeScreen] Triggering Post-Connect Ad Check...",
              );
              _adManagerService.fetchLatestAds();
            }
          });
        }
      }
    });

    _timerUpdater = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });

    // Start ping monitoring for auto-switch
    _startPingMonitoring();

    // Check admin status for UI banner
    if (Platform.isWindows) {
      _nativeVpnService.isAdmin().then((val) {
        if (mounted) setState(() => _isAdmin = val);
      });
    }
  }

  @override
  void dispose() {
    _funnelSubscription?.cancel();
    _vpnStatusSubscription?.cancel();
    _statsSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _timeWalletService.removeListener(_onTimeChanged);
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
    if (_configManager.selectedConfig != null &&
        (_configManager.selectedConfig?.currentPing ?? 0) > 3000) {
      _highPingCounter++;
      AdvancedLogger.info(
        '[ConnectionHomeScreen] High ping detected. Counter: $_highPingCounter',
      );

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

    final now = DateTime.now();
    if (_lastAutoSwitchTime != null &&
        now.difference(_lastAutoSwitchTime!).inSeconds < 30) {
      AdvancedLogger.warn(
        '[AutoSwitch] Cooldown active. Auto-switch throttled to prevent Ping-Pong effect.',
      );
      return;
    }
    _lastAutoSwitchTime = now;

    _isSwitching = true;
    AdvancedLogger.info(
      '[ConnectionHomeScreen] Initiating auto-switch due to high ping',
    );
    _showToast("High ping detected. Switching to best server...");

    try {
      // Stop current VPN connection
      await _nativeVpnService.disconnect();

      // Cool-down period to allow OS to release TUN interface
      AdvancedLogger.info('Waiting for port release...');
      await Future.delayed(
        const Duration(seconds: 2),
      ); // Increased delay for safety

      // Check if user cancelled during the delay
      if (_configManager.userInitiatedDisconnect ||
          _configManager.isConnectionCancelled) {
        AdvancedLogger.warn(
          '[AutoSwitch] User initiated disconnect or cancelled during switch. Aborting.',
        );
        return;
      }

      // Use Smart Failover
      await _configManager.connectWithSmartFailover();
    } catch (e, stackTrace) {
      AdvancedLogger.error(
        '[ConnectionHomeScreen] Auto-switch failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
      _showToast("Auto-switch failed: $e");
    } finally {
      _isSwitching = false;
    }
  }

  void _onTimeChanged() {
    if (mounted) {
      setState(() {});
      // Enforced disconnection UI alert
      if (!_timeWalletService.hasTime && _configManager.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Time expired! VPN Disconnected. Please watch an ad to recharge.',
            ),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
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

  // --- AD REWARD LOGIC ---
  Future<void> _showAdSequence() async {
    if (!kEnableAds) {
      // Short-circuit: Give reward automatically if ads are disabled
      _timeWalletService.rewardTime();
      _showToast("Premium active! +1 Hour Added.");
      return;
    }

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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Claim Reward',
            style: TextStyle(color: Colors.white),
          ),
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
              child: const Text(
                'Claim +1 Hour',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );

      if (claimed == true) {
        await _timeWalletService.rewardTime();
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
    setState(() {
      _isFetching = true;
    });

    final bool hasInternet = await _connectivityService.hasInternet();

    if (!hasInternet) {
      if (mounted) {
        setState(() {
          _isFetching = false;
        });
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
      final success = await _configGistService.fetchAndApplyConfigs(
        _configManager,
      );
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "⚠️ Server list could not be loaded. Please check your connection and tap Refresh.",
            ),
            backgroundColor: Colors.orangeAccent,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      AdvancedLogger.warn("[HomeScreen] Config fetch failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isFetching = false;
        });
      }
    }

    // Check for updates (Background)
    if (mounted) {
      _configGistService.checkForUpdates(context);
    }

    // Auto Refresh on startup if enabled
    if (_autoRefreshOnStartup) {
      AdvancedLogger.info("[HomeScreen] Triggering Auto-Refresh on startup...");
      await _refreshConfigsManual();
    }

    // Auto Test if configs exist
    // Smart Startup: Skip auto-test if we already have enough good configs
    final bool haveEnoughValid = _configManager.validatedConfigs.length >= 5;

    if (!haveEnoughValid &&
        _configManager.allConfigs.isNotEmpty &&
        _autoTestOnStartup &&
        !_configManager.isConnected &&
        mounted) {
      AdvancedLogger.info(
        "[HomeScreen] Triggering Auto-Test (Need valid configs)...",
      );
      _runFunnelTest();
    } else if (haveEnoughValid) {
      AdvancedLogger.info(
        "[HomeScreen] Smart Startup: Skipping Auto-Test (Have ${_configManager.validatedConfigs.length} valid configs).",
      );
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

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _autoTestOnStartup = prefs.getBool('autoTestOnStartup') ?? true;
        _autoRefreshOnStartup = prefs.getBool('autoRefreshOnStartup') ?? true;
      });
    } catch (e) {
      AdvancedLogger.error('Failed to load preferences: $e');
    }
  }

  Future<void> _initialize() async {
    try {
      await _loadPreferences();
      if (!_isInitialized) {
        setState(() {
          _isInitialized = true;
        });
      }
      AdvancedLogger.info('[HomeScreen] Initialized successfully');

      // Start app sequence now that preferences are loaded
      await _initAppSequence();
    } catch (e) {
      AdvancedLogger.error('[HomeScreen] Initialization failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'V2Ray',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.greenAccent),
            onPressed: _refreshConfigsManual,
            tooltip: 'Force Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long, color: Colors.amber),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LogViewerScreen()),
              );
            },
            tooltip: 'View Logs',
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddServerDialog,
        backgroundColor: Colors.blueAccent,
        tooltip: 'Add Manual Server',
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          backgroundColor: const Color(0xFF141414),
          color: Colors.blueAccent,
          onRefresh: _refreshConfigsManual,
          child: CustomScrollView(
            // ignore: deprecated_member_use
            cacheExtent: 1000,
            slivers: [
              // 1. Banner for Admin Warning (Windows only)
              if (Platform.isWindows) _AdminWarningBanner(isAdmin: _isAdmin),
              const SliverToBoxAdapter(child: _AdBannerSection()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _SubscriptionCard(
                        hasTime: _timeWalletService.hasTime,
                        remainingSeconds: _timeWalletService.remainingSeconds,
                        onAddTime: _showAdSequence,
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.autorenew, color: Colors.blueAccent),
                                const SizedBox(width: 8),
                                const Text(
                                  'Auto Switch',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Switch(
                              value: _configManager.isAutoSwitchEnabled,
                              activeThumbColor: Colors.blueAccent,
                              onChanged: (val) {
                                setState(() {
                                  _configManager.isAutoSwitchEnabled = val;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      ListenableBuilder(
                        listenable: _configManager,
                        builder: (context, _) => Column(
                          children: [
                            _ConnectionStatus(
                              isConnected: _configManager.isConnected,
                              connectionStatus: _configManager.connectionStatus,
                              rxBytes: _rxBytes,
                              txBytes: _txBytes,
                            ),
                            const SizedBox(height: 12),
                            _ConnectButton(
                              isConnected: _configManager.isConnected,
                              isConnecting: _isNativeOperationInProgress,
                              onRefresh: _refreshConfigsManual,
                              onConnect: _handleConnection,
                              onSkip: _skipServer,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      ListenableBuilder(
                        listenable: _configManager,
                        builder: (context, _) => _SelectedConfigView(
                          config: _configManager.selectedConfig,
                          activeTestIds: _activeTestIds,
                          onRunSingleTest: _runSingleTest,
                          onToggleFavorite: (id) async {
                            await _configManager.toggleFavorite(id);
                          },
                          onDelete: (config) async {
                            final confirm = await _showDeleteConfirmationDialog(
                              config,
                            );
                            if (confirm && mounted) {
                              await _configManager.deleteConfig(config.id);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 25),
                      _AutoTestToggleGroup(
                        autoTestOnStartup: _autoTestOnStartup,
                        autoRefreshOnStartup: _autoRefreshOnStartup,
                        onAutoTestChanged: (val) {
                          setState(() {
                            _autoTestOnStartup = val;
                          });
                          _savePreferences();
                        },
                        onAutoRefreshChanged: (val) {
                          setState(() {
                            _autoRefreshOnStartup = val;
                          });
                          _savePreferences();
                        },
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    height: 60,
                    child: UniversalAdWidget(slot: 'home_banner_bottom'),
                  ),
                ),
              ),
              // Progress Bar & Overlay
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: Column(
                    children: [
                      if (_testProgress.isNotEmpty &&
                          _testProgress != "Completed" &&
                          _testProgress != "Stopped")
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.blueAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _testProgress,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.stop,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () {
                                  _funnelService.stop();
                                  _showToast("Test Stopped");
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.list,
                        color: Colors.blueAccent,
                        size: 22,
                      ),
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
                        icon: const Icon(
                          Icons.delete_sweep,
                          color: Colors.redAccent,
                        ),
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
                delegate: SliverTabBarDelegate(
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
                        text:
                            'Valid (${_configManager.validatedConfigs.length})',
                      ),
                      Tab(
                        icon: const Icon(Icons.star, size: 18),
                        text: 'Favs (${_configManager.favoriteConfigs.length})',
                      ),
                    ],
                  ),
                  backgroundColor: const Color(0xFF0A0A0A),
                ),
              ),
              AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) => ListenableBuilder(
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
                      if (_isFetching) {
                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => const ShimmerConfigCard(),
                            childCount: 6,
                          ),
                        );
                      }

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
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final config = configs[index];
                        return ConfigCard(
                          config: config,
                          isSelected:
                              _configManager.selectedConfig?.id == config.id,
                          isTesting: _activeTestIds.contains(config.id),
                          onTap: () async {
                            _configManager.selectConfig(config);

                            if (_configManager.isAutoSwitchEnabled) {
                              if (_configManager.isConnected) {
                                // Start the switch process properly within ConfigManager to avoid race conditions
                                await _configManager.switchConfig(config);
                              }
                            } else {
                              // Forced manual connect
                              try {
                                await _configManager.connectManual(config);
                              } catch (e) {
                                _showToast('Connection failed: $e');
                              }
                            }
                          },
                          onTestLatency: () => _runSingleTest(config),
                          onTestSpeed: () => _runSingleTest(config),
                          onToggleFavorite: () async {
                            await _configManager.toggleFavorite(config.id);
                          },
                          onDelete: () async {
                            final confirm = await _showDeleteConfirmationDialog(
                              config,
                            );
                            if (confirm && mounted) {
                              await _configManager.deleteConfig(config.id);
                            }
                          },
                        );
                      }, childCount: configs.length),
                    );
                  },
                ),
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
    // Check if user wants to disconnect or cancel connecting
    final status = _configManager.connectionStatus.toLowerCase();
    if (_configManager.isConnected || status.contains('connecting')) {
      await _configManager.stopAllOperations();
      return;
    }

    // Now check if other operations are in progress (testing, fetching, switching)
    if (status.contains('disconnecting') ||
        status.contains('testing') ||
        _activeTestIds.isNotEmpty ||
        _isFetching ||
        _isSwitching) {
      return;
    }

    try {
      // Network Check
      if (!await _connectivityService.hasInternet()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No internet connection'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      _configManager.setConnected(false, status: 'Connecting...');

      // Access Check
      final access = _timeWalletService;
      if (!access.hasTime) {
        await _showAdSequence();
        if (!access.hasTime) {
          _configManager.setConnected(false, status: 'Disconnected');
          return;
        }
      }

      if (_configManager.allConfigs.isEmpty) {
        _showToast("No configurations available. Please refresh.");
        _configManager.setConnected(false, status: 'Disconnected');
        return;
      }

      // 1. SMART WAIT LOOP
      // If we have no valid configs yet, wait for the Funnel
      if (_configManager.validatedConfigs.isEmpty) {
        setState(
          () =>
              _configManager.setConnected(false, status: 'Testing servers...'),
        );

        // Start Funnel if not running
        _funnelService.startFunnel(retestDead: false); // Prioritize fresh ones

        int waits = 0;
        while (_configManager.validatedConfigs.isEmpty &&
            waits < 15 &&
            !_configManager.isConnectionCancelled) {
          await Future.delayed(const Duration(seconds: 1));
          waits++;
        }

        if (_configManager.isConnectionCancelled) {
          _configManager.setConnected(false, status: 'Disconnected');
          return;
        }

        if (_configManager.validatedConfigs.isEmpty) {
          _showToast("No accessible servers found. Please update list.");
          _configManager.setConnected(false, status: 'Failed');
          return;
        }
      }

      // 2. Delegate to Service (Smart Failover)
      await _configManager.connectWithSmartFailover();
    } catch (e) {
      AdvancedLogger.error('Connection failed: $e');
      _configManager.setConnected(false, status: 'Failed');
      _showToast('Connection failed. Please try again.');
    }
  }

  Future<void> _runSingleTest(VpnConfigWithMetrics config) async {
    if (_isNativeOperationInProgress) return;
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
    if (_isNativeOperationInProgress) return;
    _showToast('Refreshing configs...');
    setState(() {
      _isFetching = true;
    });
    try {
      await _configGistService.fetchAndApplyConfigs(
        _configManager,
        force: true,
      );
      _showToast('Refresh completed');
    } catch (e) {
      _showToast('Failed to refresh configs: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isFetching = false;
        });
      }
    }
  }

  Future<void> _skipServer() async {
    if (_isNativeOperationInProgress) return;
    try {
      if (_configManager.isConnected) {
        await _nativeVpnService.disconnect();
        // Short delay to allow native cleanup
        await Future.delayed(const Duration(milliseconds: 500));
      }
      final success = await _configManager.skipToNext(
        sourceList: _getCurrentList(),
      );
      if (!success) {
        _showToast("No other valid servers available.");
      }
    } catch (e) {
      AdvancedLogger.error('Skip failed: $e');
      _configManager.setConnected(false, status: 'Failed');
    }
  }

  List<VpnConfigWithMetrics> _getCurrentList() {
    switch (_tabController.index) {
      case 1:
        return _configManager.validatedConfigs;
      case 2:
        return _configManager.favoriteConfigs;
      case 0:
      default:
        return _configManager.allConfigs;
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

  // _buildAppHeader Removed

  Future<void> _showAddServerDialog() async {
    final TextEditingController urlController = TextEditingController();

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Add Manual Server',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: urlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'vmess:// or vless:// ...',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            maxLines: 3,
            minLines: 1,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ScaleOnTap(
              onTap: () async {
                final url = urlController.text.trim();
                if (url.isNotEmpty) {
                  Navigator.of(context).pop();
                  // Constraint: Properly split multiline input for multiple configs
                  final lines = url
                      .split(RegExp(r'\r?\n|\s+'))
                      .where((e) => e.trim().isNotEmpty)
                      .toList();
                  final added = await _configManager.addConfigs(
                    lines.isNotEmpty ? lines : [url],
                  );
                  if (added > 0) {
                    _showToast("Server added successfully!");
                    setState(() {});
                  } else {
                    _showToast(
                      "Failed to add server. Invalid format or already exists.",
                    );
                  }
                } else {
                  _showToast("Please enter a valid URL.");
                }
              },
              child: IgnorePointer(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                  ),
                  child: const Text('Add', style: TextStyle(color: Colors.white)),
                  onPressed: () {},
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoTestOnStartup', _autoTestOnStartup);
    await prefs.setBool('autoRefreshOnStartup', _autoRefreshOnStartup);
  }

  void _showSmartCleanupDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.delete_forever,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'حذف همه کانفیگ‌ها',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Vazirmatn',
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _configManager.clearAllData();
                  _showToast("همه کانفیگ‌ها حذف شدند");
                },
              ),
              ListTile(
                leading: const Icon(Icons.wifi_off, color: Colors.orangeAccent),
                title: const Text(
                  'حذف کانفیگ‌های غیرقابل دسترس',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Vazirmatn',
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final removed = await _configManager.removeConfigs(
                    dead: true,
                  );
                  _showToast("$removed کانفیگ غیرقابل دسترس حذف شد");
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.signal_cellular_connected_no_internet_4_bar,
                  color: Colors.yellowAccent,
                ),
                title: const Text(
                  'حذف کانفیگ‌های ضعیف',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Vazirmatn',
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final removed = await _configManager.removeConfigs(
                    weak: true,
                  );
                  _showToast("$removed کانفیگ ضعیف حذف شد");
                },
              ),
              ListTile(
                leading: const Icon(Icons.speed, color: Colors.blueAccent),
                title: const Text(
                  'حذف کانفیگ‌های بدون تست سرعت',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Vazirmatn',
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final removed = await _configManager.removeConfigs(
                    untestedSpeed: true,
                  );
                  _showToast("$removed کانفیگ بدون تست سرعت حذف شد");
                },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.close, color: Colors.grey),
                title: const Text(
                  'لغو',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Vazirmatn',
                  ),
                ),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _showDeleteConfirmationDialog(
    VpnConfigWithMetrics config,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              'Delete Config',
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              'Delete ${config.name}?',
              style: const TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _AdminWarningBanner extends StatelessWidget {
  final bool isAdmin;
  const _AdminWarningBanner({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    if (isAdmin) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        color: Colors.amberAccent.withValues(alpha: 0.2),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: const [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.amberAccent,
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "For better connectivity, please run iVPN as Administrator.",
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
Widget buildConnectButtonForTest({
  required bool isConnected,
  required bool isConnecting,
  required VoidCallback onRefresh,
  required VoidCallback onConnect,
  required VoidCallback onSkip,
}) {
  return _ConnectButton(
    isConnected: isConnected,
    isConnecting: isConnecting,
    onRefresh: onRefresh,
    onConnect: onConnect,
    onSkip: onSkip,
  );
}

@visibleForTesting
Widget buildConnectionStatusForTest({
  required bool isConnected,
  required String connectionStatus,
  required int rxBytes,
  required int txBytes,
}) {
  return _ConnectionStatus(
    isConnected: isConnected,
    connectionStatus: connectionStatus,
    rxBytes: rxBytes,
    txBytes: txBytes,
  );
}

class _AdBannerSection extends StatelessWidget {
  const _AdBannerSection();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: UniversalAdWidget(slot: 'home_banner_top'),
    );
  }
}

class _SubscriptionCard extends StatefulWidget {
  final bool hasTime;
  final int remainingSeconds;
  final VoidCallback onAddTime;

  const _SubscriptionCard({
    required this.hasTime,
    required this.remainingSeconds,
    required this.onAddTime,
  });

  @override
  State<_SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends State<_SubscriptionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        leading: const Icon(
          Icons.workspace_premium,
          color: Colors.amber,
          size: 32,
        ),
        title: const Text(
          'Free Plan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          widget.hasTime
              ? '${(widget.remainingSeconds ~/ 3600)}h ${((widget.remainingSeconds % 3600) ~/ 60)}m remaining'
              : 'No active plan',
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueAccent.withValues(alpha: 0.6),
                      blurRadius: _glowAnimation.value + 4.0,
                      spreadRadius: _glowAnimation.value / 2,
                    ),
                  ],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: widget.onAddTime,
                  child: const Text('🎁 Add Time'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  final bool isConnected;
  final String connectionStatus;
  final int rxBytes;
  final int txBytes;

  const _ConnectionStatus({
    required this.isConnected,
    required this.connectionStatus,
    required this.rxBytes,
    required this.txBytes,
  });

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    if (isConnected) {
      statusColor = Colors.greenAccent;
    } else if (connectionStatus == 'Failed' ||
        connectionStatus.contains('Error')) {
      statusColor = Colors.redAccent;
    } else {
      statusColor = Colors.grey;
    }

    return Column(
      children: [
        Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              connectionStatus,
              key: ValueKey<String>(connectionStatus),
              style: TextStyle(
                color: statusColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        if (isConnected)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.arrow_downward,
                  color: Colors.greenAccent,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatBytes(rxBytes),
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(width: 16),
                const Icon(
                  Icons.arrow_upward,
                  color: Colors.blueAccent,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatBytes(txBytes),
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ConnectButton extends StatelessWidget {
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback onRefresh;
  final VoidCallback onConnect;
  final VoidCallback onSkip;

  const _ConnectButton({
    required this.isConnected,
    required this.isConnecting,
    required this.onRefresh,
    required this.onConnect,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Refresh Button (Left Side)
        Positioned(
          left: 30,
          child: Column(
            children: [
              Tooltip(
                message: 'Refresh Servers',
                child: ScaleOnTap(
                  onTap: onRefresh,
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.refresh_rounded,
                      size: 32,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Refresh",
                style: TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ),

        // Main Connect Button
        Center(
          child: ScaleOnTap(
            onTap: onConnect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isConnected
                      ? [
                          const Color(0xFF11998E),
                          const Color(0xFF38EF7D),
                        ] // Green/Teal
                      : (isConnecting
                          ? [
                              const Color(0xFFF2994A),
                              const Color(0xFFF2C94C),
                            ] // Orange/Yellow
                          : [
                              const Color(0xFF4A5568),
                              const Color(0xFF2D3748),
                            ]), // Dark Grey
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isConnected
                            ? const Color(0xFF38EF7D)
                            : (isConnecting
                                ? const Color(0xFFF2994A)
                                : Colors.black))
                        .withValues(
                      alpha: isConnected || isConnecting ? 0.5 : 0.3,
                    ),
                    blurRadius: isConnected || isConnecting ? 25 : 15,
                    spreadRadius: isConnected || isConnecting ? 8 : 2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: isConnecting
                        ? const SizedBox(
                            key: ValueKey('connecting_spinner'),
                            width: 50,
                            height: 50,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(
                            Icons.power_settings_new,
                            key: ValueKey('connect_icon'),
                            size: 60,
                            color: Colors.white,
                          ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      isConnected
                          ? 'CONNECTED'
                          : (isConnecting ? 'CONNECTING' : 'CONNECT'),
                      key: ValueKey(
                        isConnected
                            ? 'CONNECTED'
                            : (isConnecting ? 'CONNECTING' : 'CONNECT'),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Skip Button (Right Side)
        Positioned(
          right: 30,
          child: Column(
            children: [
              Tooltip(
                message: 'Next Server',
                child: ScaleOnTap(
                  onTap: onSkip,
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.skip_next_rounded,
                      size: 32,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Skip",
                style: TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectedConfigView extends StatelessWidget {
  final VpnConfigWithMetrics? config;
  final Set<String> activeTestIds;
  final void Function(VpnConfigWithMetrics) onRunSingleTest;
  final void Function(String) onToggleFavorite;
  final void Function(VpnConfigWithMetrics) onDelete;

  const _SelectedConfigView({
    required this.config,
    required this.activeTestIds,
    required this.onRunSingleTest,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (config == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ConfigCard(
        config: config!,
        isSelected: true,
        isTesting: activeTestIds.contains(config!.id),
        onTap: () {}, // Already selected
        onTestLatency: () => onRunSingleTest(config!),
        onTestSpeed: () => onRunSingleTest(config!),
        onToggleFavorite: () => onToggleFavorite(config!.id),
        onDelete: () => onDelete(config!),
      ),
    );
  }
}

class _AutoTestToggleGroup extends StatelessWidget {
  final bool autoTestOnStartup;
  final bool autoRefreshOnStartup;
  final ValueChanged<bool> onAutoTestChanged;
  final ValueChanged<bool> onAutoRefreshChanged;

  const _AutoTestToggleGroup({
    required this.autoTestOnStartup,
    required this.autoRefreshOnStartup,
    required this.onAutoTestChanged,
    required this.onAutoRefreshChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            'Auto-Test on Startup',
            style: TextStyle(color: Colors.white),
          ),
          value: autoTestOnStartup,
          activeThumbColor: Colors.blueAccent,
          onChanged: onAutoTestChanged,
        ),
        SwitchListTile(
          title: const Text(
            'Auto-Refresh on Startup',
            style: TextStyle(color: Colors.white),
          ),
          value: autoRefreshOnStartup,
          activeThumbColor: Colors.blueAccent,
          onChanged: onAutoRefreshChanged,
        ),
      ],
    );
  }
}
