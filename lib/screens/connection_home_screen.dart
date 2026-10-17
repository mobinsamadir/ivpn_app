import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final ValueNotifier<bool> _isFetching = ValueNotifier<bool>(false);

  final ValueNotifier<Set<String>> _activeTestIds = ValueNotifier<Set<String>>({});

  // Connection Control
  // CRITICAL FIX: Debounce Auto-Switch
  bool _isSwitching = false;
  String _connectionFlowState = "idle"; // idle, requesting_permission, connecting
  // Native Operation check
  bool get _isNativeOperationInProgress {
    final status = _configManager.connectionStatus.toLowerCase();
    return status.contains('disconnecting') ||
        status.contains('testing') ||
        _activeTestIds.value.isNotEmpty ||
        _isFetching.value ||
        _isSwitching;
  }

  bool _wasVpnConnected = false;

  bool get _isConnectingToVpn {
    final status = _configManager.connectionStatus.toLowerCase();
    return _connectionFlowState == 'connecting' ||
        _connectionFlowState == 'requesting_permission' ||
        status.contains('connecting');
  }

  String _lastNativeStatus = "DISCONNECTED";
  final ValueNotifier<bool> _isAdmin = ValueNotifier<bool>(true);

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
  final ValueNotifier<String> _testProgress = ValueNotifier<String>("");

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

    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        // Rebuild handled by AnimatedBuilder
      }
    });

    _initialize();
    WidgetsBinding.instance.addObserver(this);

    // AccessManager Listener
    _timeWalletService.init().then((_) {
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
      if (mounted) _testProgress.value = msg;
    });

    // Listen to VPN Traffic Stats
    _statsSubscription = _nativeVpnService.statsStream.listen((stats) {
      if (mounted) {
        setState(() {
          _rxBytes = stats['rx'] ?? 0;
          _txBytes = stats['tx'] ?? 0;
        });
      }
    });

    // VPN Connection Status Listener
    _vpnStatusSubscription = _nativeVpnService.connectionStatusStream.listen((
      status,
    ) {
      AdvancedLogger.info(
        '[ConnectionHomeScreen] Received VPN status update: $status',
      );
      if (mounted) {
        _lastNativeStatus = status;
        // Update the connection status in ConfigManager to reflect the actual VPN status
        _configManager.setConnected(
          status == 'CONNECTED',
          status: _getConnectionStatusMessage(status),
        );

        if (status == 'DISCONNECTED' ||
            status.contains('Administrator privileges required') ||
            status.contains('Administrator')) {
          if (status.contains('Administrator privileges required') ||
              status.contains('Administrator')) {
            _isAdmin.value = false;
            _configManager.userInitiatedDisconnect =
                true; // Stop auto-switching
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Run as Administrator is required'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }

          _rxBytes = 0;
          _txBytes = 0;
          final wasConnected = _wasVpnConnected;
          _wasVpnConnected = false;

          if (wasConnected &&
              !_configManager.userInitiatedDisconnect &&
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
                      'Connection dropped repeatedly. Auto-switch stopped.',
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

              }
            }
          }
          _configManager.userInitiatedDisconnect = false;
          _configManager.isConnectionCancelled = false;
        }

        // NEW: Post-Connect Logic (Anti-Censorship)
        if (status == 'CONNECTED') {
          _wasVpnConnected = true;
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



    // Start ping monitoring for auto-switch
    _startPingMonitoring();

    // Check admin status for UI banner
    if (Platform.isWindows) {
      _nativeVpnService.isAdmin().then((val) {
        if (mounted) _isAdmin.value = val;
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

    _pingMonitorTimer?.cancel();
    _testProgress.dispose();
    _isFetching.dispose();
    _activeTestIds.dispose();
    _isAdmin.dispose();
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
            ScaleOnTap(
              onTap: () => Navigator.pop(context, true),
              child: IgnorePointer(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text(
                    'Claim +1 Hour',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
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
    _isFetching.value = true;

    final bool hasInternet = await _connectivityService.hasInternet();

    if (!hasInternet) {
      if (mounted) {
        _isFetching.value = false;
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
    if (_autoRefreshOnStartup) {
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
          _isFetching.value = false;
        }
      }
    } else {
      if (mounted) {
        _isFetching.value = false;
      }
    }

    // Check for updates (Background)
    if (mounted) {
      _configGistService.checkForUpdates(context);
    }

    // Auto Test on startup if enabled (delayed slightly so UI finishes smooth initial draw)
    if (_autoTestOnStartup && mounted) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted && !_configManager.isConnected) {
          AdvancedLogger.info("[HomeScreen] Triggering Auto-Test in background...");
          _runSmartAutoTest();
        }
      });
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
        _isInitialized = true;
        if (mounted) setState(() {});
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
          'iVPN',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Tooltip(
            message: 'Force Refresh',
            child: ScaleOnTap(
              onTap: _refreshConfigsManual,
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.refresh, color: Colors.greenAccent),
              ),
            ),
          ),
          Tooltip(
            message: 'Logs & Diagnostics',
            child: ScaleOnTap(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LogViewerScreen()),
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.terminal_rounded, color: Colors.amberAccent),
              ),
            ),
          ),
          Tooltip(
            message: 'Settings',
            child: ScaleOnTap(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.settings, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Tooltip(
        message: 'Add Manual Server',
        child: ScaleOnTap(
          onTap: _showAddServerDialog,
          child: IgnorePointer(
            child: FloatingActionButton(
              onPressed: _showAddServerDialog,
              backgroundColor: Colors.blueAccent,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ),
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
              if (Platform.isWindows)
                ValueListenableBuilder<bool>(
                  valueListenable: _isAdmin,
                  builder: (context, isAdmin, _) => _AdminWarningBanner(isAdmin: isAdmin),
                ),
              const SliverToBoxAdapter(child: _AdBannerSection()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      ListenableBuilder(
                        listenable: _timeWalletService,
                        builder: (context, _) => _SubscriptionCard(
                          hasTime: _timeWalletService.hasTime,
                          remainingSeconds: _timeWalletService.remainingSeconds,
                          onAddTime: _showAdSequence,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: ListenableBuilder(
                          listenable: _configManager,
                          builder: (context, _) => ScaleOnTap(
                            onTap: () {
                              _configManager.isAutoSwitchEnabled =
                                  !_configManager.isAutoSwitchEnabled;
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _configManager.isAutoSwitchEnabled
                                    ? Colors.blueAccent.withValues(alpha: 0.15)
                                    : const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _configManager.isAutoSwitchEnabled
                                      ? Colors.blueAccent.withValues(alpha: 0.5)
                                      : Colors.white12,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.autorenew_rounded,
                                    size: 16,
                                    color: _configManager.isAutoSwitchEnabled
                                        ? Colors.blueAccent
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Auto Switch',
                                    style: TextStyle(
                                      color: _configManager.isAutoSwitchEnabled
                                          ? Colors.white
                                          : Colors.grey,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _configManager.isAutoSwitchEnabled
                                          ? const Color(0xFF00E676)
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
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
                              isConnecting: _isConnectingToVpn,
                              onRefresh: _refreshConfigsManual,
                              onConnect: _handleConnection,
                              onSkip: _skipServer,
                            ),
                            ValueListenableBuilder<VpnConfigWithMetrics?>(
                              valueListenable:
                                  _funnelService.bestDiscoveredConfigNotifier,
                              builder: (context, bestConfig, _) {
                                final candidate = bestConfig ?? _configManager.fastestValidatedConfig;
                                if (candidate == null ||
                                    _configManager.isConnected ||
                                    candidate.id == _configManager.selectedConfig?.id) {
                                  return const SizedBox.shrink();
                                }
                                return _QuickConnectSuggestionCard(
                                  config: candidate,
                                  onQuickConnect: () =>
                                      _quickConnectToConfig(candidate),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListenableBuilder(
                        listenable: _configManager,
                        builder: (context, _) => ValueListenableBuilder<Set<String>>(
                          valueListenable: _activeTestIds,
                          builder: (context, activeTestIds, _) => _SelectedConfigView(
                            config: _configManager.selectedConfig,
                            activeTestIds: activeTestIds,
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
                      ),
                      const SizedBox(height: 10),
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
                      ValueListenableBuilder<String>(
                        valueListenable: _testProgress,
                        builder: (context, progressValue, child) {
                          if (progressValue.isNotEmpty &&
                              progressValue != "Completed" &&
                              progressValue != "Stopped") {
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.blueAccent.withValues(
                                    alpha: 0.3,
                                  ),
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
                                      progressValue,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Stop Test',
                                    child: ScaleOnTap(
                                      onTap: () {
                                        _funnelService.stop();
                                        _showToast("Test Stopped");
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(
                                          Icons.stop,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
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
                      Tooltip(
                        message: 'Test All Connections (Funnel)',
                        child: ScaleOnTap(
                          onTap: _runSmartAutoTest,
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(Icons.speed, color: Colors.blueAccent),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Cleanup Configs',
                        child: ScaleOnTap(
                          onTap: _showSmartCleanupDialog,
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(Icons.delete_sweep,
                                color: Colors.redAccent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: _configManager,
                builder: (context, _) => SliverPersistentHeader(
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
                        icon: const Icon(Icons.public, size: 18),
                        text: 'Location (${_getUniqueLocationsCount()})',
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
              ),
              ListenableBuilder(
                listenable: Listenable.merge([_tabController, _configManager, _isFetching, _activeTestIds]),
                builder: (context, _) {
                    if (_tabController.index == 2) {
                      return _buildLocationsSliver();
                    }

                    List<VpnConfigWithMetrics> configs;
                    switch (_tabController.index) {
                      case 1:
                        configs = _configManager.validatedConfigs;
                        break;
                      case 3:
                        configs = _configManager.favoriteConfigs;
                        break;
                      case 0:
                      default:
                        configs = _configManager.allConfigs;
                    }

                    if (configs.isEmpty) {
                      if (_isFetching.value) {
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
                          isTesting: _activeTestIds.value.contains(config.id),
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
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ),
        ),
      ),
    );
  }

  // --- LOGIC METHODS ---
  Future<void> _handleConnection() async {
    // Check if user wants to disconnect or cancel connecting first
    final status = _configManager.connectionStatus.toLowerCase();
    final bool isConnectingOrConnected = _configManager.isConnected ||
        status.contains('connecting') ||
        _connectionFlowState == 'connecting' ||
        _connectionFlowState == 'requesting_permission';

    if (isConnectingOrConnected) {
      AdvancedLogger.info("[HomeScreen] Connect button tapped to cancel / disconnect");
      _connectionFlowState = 'disconnecting';
      _wasVpnConnected = false;
      try {
        await _configManager.stopAllOperations();
      } finally {
        _connectionFlowState = 'idle';
      }
      return;
    }

    if (_connectionFlowState != 'idle') {
      AdvancedLogger.warn("[ConnectionHomeScreen] Ignoring connect tap: currently $_connectionFlowState");
      return;
    }

    // Now check if other operations are in progress (testing, fetching, switching)
    if (status.contains('disconnecting') ||
        status.contains('testing') ||
        _activeTestIds.value.isNotEmpty ||
        _isFetching.value ||
        _isSwitching) {
      return;
    }

    try {
      _connectionFlowState = 'requesting_permission';

      // Network Check
      if (!await _connectivityService.hasInternet()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No internet connection'),
            backgroundColor: Colors.redAccent,
          ),
        );
        _connectionFlowState = 'idle';
        return;
      }

      _configManager.setConnected(false, status: 'Checking permissions...');

      // **CRITICAL INVARIANT: EXPLICIT VPN PERMISSION CHECK HERE**
      bool hasPermission = await _nativeVpnService.hasVpnPermission();
      if (!hasPermission) {
        _configManager.setConnected(false, status: 'Waiting for permission...');
        hasPermission = await _nativeVpnService.requestVpnPermission();
        if (!hasPermission) {
           _configManager.setConnected(false, status: 'Permission Denied');
           _showToast("VPN Permission is required to connect or test servers.");
           _connectionFlowState = 'idle';
           return;
        }
      }

      _connectionFlowState = 'connecting';
      _configManager.setConnected(false, status: 'Connecting...');

      // Access Check
      final access = _timeWalletService;
      if (!access.hasTime) {
        await _showAdSequence();
        if (!access.hasTime) {
          _configManager.setConnected(false, status: 'Disconnected');
          _connectionFlowState = 'idle';
          return;
        }
      }

      if (_configManager.allConfigs.isEmpty) {
        _showToast("No configurations available. Please refresh.");
        _configManager.setConnected(false, status: 'Disconnected');
        _connectionFlowState = 'idle';
        return;
      }

      // 1. SMART WAIT LOOP
      // Only run discovery wait loop if auto-switch is ENABLED and no candidate is validated yet!
      // If auto-switch is disabled OR user manually selected a config, connect immediately without waiting!
      final bool isAutoSwitch = _configManager.isAutoSwitchEnabled;
      final bool hasManualSelection = _configManager.selectedConfig != null;

      if (isAutoSwitch && !hasManualSelection && _configManager.validatedConfigs.isEmpty) {
        _configManager.setConnected(false, status: 'Finding fastest servers...');

        // Start Funnel with lightweight connectivity probe (no heavy speed test)
        _funnelService.startFunnel(retestDead: false, enableSpeedTest: false);

        int waits = 0;
        const int maxWaits = 25;
        while (waits < maxWaits && !_configManager.isConnectionCancelled) {
          await Future.delayed(const Duration(seconds: 1));
          waits++;
          
          final count = _configManager.validatedConfigs.length;
          _configManager.setConnected(
            false,
            status: count > 0
                ? 'Found $count candidates ($waits/${maxWaits}s)...'
                : 'Finding fastest servers ($waits/${maxWaits}s)...',
          );

          if (_configManager.validatedConfigs.isNotEmpty) {
            final lowestPing = _configManager.validatedConfigs
                .map((c) => c.currentPing)
                .where((p) => p > 0)
                .fold<int>(9999, (prev, elem) => elem < prev ? elem : prev);
            // If we found a low ping server (<250ms), or 2+ candidates, or 5s passed with at least 1 candidate, connect immediately!
            if (lowestPing < 250 || count >= 2 || (count >= 1 && waits >= 5)) {
              break;
            }
          }
        }

        if (_configManager.isConnectionCancelled) {
          _configManager.setConnected(false, status: 'Disconnected');
          return;
        }

        if (_configManager.validatedConfigs.isEmpty) {
          AdvancedLogger.warn(
            "[HomeScreen] Discovery grace period ended without validated servers. Disconnecting...",
          );
          _showToast("No valid server found.");
          _configManager.setConnected(false, status: 'Failed');
          _connectionFlowState = 'idle';
          return;
        }
      }

      // Final check: Validate only if auto-switch is enabled
      if (isAutoSwitch) {
        final bool canConnect = _configManager.validatedConfigs.isNotEmpty ||
            (_configManager.selectedConfig?.isValidated ?? false);
        if (!canConnect) {
          AdvancedLogger.warn(
            "[HomeScreen] Cannot connect: No validated configurations available.",
          );
          _showToast("No valid configurations available.");
          _configManager.setConnected(false, status: 'Failed');
          _connectionFlowState = 'idle';
          return;
        }
      } else {
        if (_configManager.allConfigs.isEmpty) {
          _showToast("No configurations available.");
          _configManager.setConnected(false, status: 'Failed');
          _connectionFlowState = 'idle';
          return;
        }
      }

      // Stop FunnelService before connecting so it doesn't hold locks/ports
      await _funnelService.stop();

      // 2. Delegate to Service (Smart Failover)
      await _configManager.connectWithSmartFailover();
    } catch (e) {
      AdvancedLogger.error('Connection failed: $e');
      _configManager.setConnected(false, status: 'Failed');
      _showErrorWithLogAction('Connection failed. Tap to view logs.');
    } finally {
      if (_connectionFlowState != 'disconnecting') _connectionFlowState = 'idle';
    }
  }

  Future<void> _quickConnectToConfig(VpnConfigWithMetrics config) async {
    if (_isNativeOperationInProgress || _connectionFlowState != 'idle') return;
    try {
      AdvancedLogger.info(
        "[HomeScreen] Quick Connect triggered to ${config.name} (${config.currentPing}ms)",
      );
      await _funnelService.stop();
      _configManager.selectConfig(config);
      _connectionFlowState = 'connecting';
      _configManager.setConnected(false, status: 'Connecting to ${config.name}...');
      await _configManager.connectWithSmartFailover();
    } catch (e) {
      AdvancedLogger.error("Quick Connect failed: $e");
    } finally {
      if (_connectionFlowState != 'disconnecting') _connectionFlowState = 'idle';
    }
  }

  Future<void> _runSingleTest(VpnConfigWithMetrics config) async {
    if (_isNativeOperationInProgress) return;
    try {
      if (mounted) _activeTestIds.value = {..._activeTestIds.value, config.id};
      _showToast('Testing ${config.name}...');
      
      final nativeService = NativeVpnService();
      bool hasPermission = await nativeService.requestVpnPermission();
      if (!hasPermission) {
        _showToast('Waiting for VPN permission...');
        await Future.delayed(const Duration(seconds: 2));
      }

      final result = await _ephemeralTester.runTest(config);
      if (result.failureReason != null && result.failureReason!.contains('VPN Permission Required')) {
        _showToast('VPN Permission Required.');
        return;
      }
      await _configManager.updateConfigDirectly(result);
      _showToast('Test complete. Stage: ${result.funnelStage}');
    } catch (e) {
      if (e.toString().contains('PERMISSION_DENIED')) {
         _showToast('VPN Permission Denied.');
      } else {
         _showToast('Test failed: $e');
      }
    } finally {
      if (mounted) _activeTestIds.value = {..._activeTestIds.value}..remove(config.id);
    }
  }

  Future<void> _refreshConfigsManual() async {
    if (!mounted) return;
    if (_isNativeOperationInProgress) return;
    _showToast('Refreshing configs...');
    _isFetching.value = true;
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
        _isFetching.value = false;
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

  int _getUniqueLocationsCount() {
    final codes = <String>{};
    for (final c in _configManager.allConfigs) {
      codes.add(c.countryCode ?? 'GLOBAL');
    }
    return codes.length;
  }

  String _countryCodeToFlag(String code) {
    final upper = code.toUpperCase();
    final flags = {
      'US': '🇺🇸', 'DE': '🇩🇪', 'TR': '🇹🇷', 'IR': '🇮🇷',
      'GB': '🇬🇧', 'FR': '🇫🇷', 'JP': '🇯🇵', 'KR': '🇰🇷',
      'CN': '🇨🇳', 'RU': '🇷🇺', 'NL': '🇳🇱', 'CA': '🇨🇦',
      'AU': '🇦🇺', 'SG': '🇸🇬', 'IN': '🇮🇳', 'BR': '🇧🇷',
      'IT': '🇮🇹', 'ES': '🇪🇸', 'SE': '🇸🇪', 'CH': '🇨🇭',
      'NO': '🇳🇴', 'FI': '🇫🇮', 'DK': '🇩🇰', 'PL': '🇵🇱',
      'CZ': '🇨🇿', 'HU': '🇭🇺', 'AT': '🇦🇹', 'BE': '🇧🇪',
      'IE': '🇮🇪', 'PT': '🇵🇹', 'GR': '🇬🇷', 'RO': '🇷🇴',
      'BG': '🇧🇬', 'HR': '🇭🇷', 'SK': '🇸🇰', 'SI': '🇸🇮',
    };
    if (flags.containsKey(upper)) return flags[upper]!;
    if (upper.length == 2) {
      try {
        final first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
        final second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
        return String.fromCharCode(first) + String.fromCharCode(second);
      } catch (_) {}
    }
    return '🌐';
  }

  String _countryCodeToName(String code) {
    const map = {
      'US': 'United States',
      'DE': 'Germany',
      'GB': 'United Kingdom',
      'FR': 'France',
      'NL': 'Netherlands',
      'FI': 'Finland',
      'TR': 'Turkey',
      'SG': 'Singapore',
      'CA': 'Canada',
      'SE': 'Sweden',
      'CH': 'Switzerland',
      'JP': 'Japan',
      'KR': 'South Korea',
      'HK': 'Hong Kong',
      'IT': 'Italy',
      'ES': 'Spain',
      'PL': 'Poland',
      'RU': 'Russia',
      'IR': 'Iran',
      'BR': 'Brazil',
      'AU': 'Australia',
      'AT': 'Austria',
      'NO': 'Norway',
    };
    return map[code.toUpperCase()] ?? (code == 'GLOBAL' ? 'Global / Other' : code);
  }

  Widget _buildLocationsSliver() {
    final Map<String, List<VpnConfigWithMetrics>> groups = {};
    for (final c in _configManager.allConfigs) {
      final code = c.countryCode ?? 'GLOBAL';
      groups.putIfAbsent(code, () => []).add(c);
    }

    if (groups.isEmpty) {
      if (_isFetching.value) {
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
                Icon(Icons.public_off, size: 64, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text(
                  'No location data available',
                  style: TextStyle(color: Colors.grey[600], fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final sortedCountryCodes = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'GLOBAL') return 1;
        if (b == 'GLOBAL') return -1;
        return groups[b]!.length.compareTo(groups[a]!.length);
      });

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final countryCode = sortedCountryCodes[index];
          final countryConfigs = groups[countryCode]!;
          final activeCount =
              countryConfigs.where((c) => c.funnelStage >= 2 && c.isAlive).length;
          final flag = _countryCodeToFlag(countryCode);
          final countryName = _countryCodeToName(countryCode);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      flag,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                  title: Text(
                    countryName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    '${countryConfigs.length} servers • $activeCount active',
                    style: TextStyle(
                      color: activeCount > 0 ? Colors.greenAccent : Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                  children: countryConfigs.map((config) {
                    return ConfigCard(
                      config: config,
                      isSelected: _configManager.selectedConfig?.id == config.id,
                      isTesting: _activeTestIds.value.contains(config.id),
                      onTap: () async {
                        _configManager.selectConfig(config);
                        if (_configManager.isAutoSwitchEnabled) {
                          if (_configManager.isConnected) {
                            await _configManager.switchConfig(config);
                          }
                        } else {
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
                        final confirm =
                            await _showDeleteConfirmationDialog(config);
                        if (confirm && mounted) {
                          await _configManager.deleteConfig(config.id);
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        },
        childCount: sortedCountryCodes.length,
      ),
    );
  }

  List<VpnConfigWithMetrics> _getCurrentList() {
    switch (_tabController.index) {
      case 1:
        return _configManager.validatedConfigs;
      case 2:
        return _configManager.allConfigs;
      case 3:
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

  void _showErrorWithLogAction(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'View Logs',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LogViewerScreen()),
            );
          },
        ),
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

    Future<void> handleAdd() async {
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
        } else {
          _showToast("Failed to add server. Invalid format or already exists.");
        }
      } else {
        _showToast("Please enter a valid URL.");
      }
    }

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
              onTap: handleAdd,
              child: IgnorePointer(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                  ),
                  onPressed: () {},
                  child: const Text(
                    'Add',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
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
                  'Delete All Servers',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _configManager.clearAllData();
                  _showToast("All servers deleted");
                },
              ),
              ListTile(
                leading: const Icon(Icons.wifi_off, color: Colors.orangeAccent),
                title: const Text(
                  'Delete Inactive Servers',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final removed = await _configManager.removeConfigs(
                    dead: true,
                  );
                  _showToast("$removed inactive servers deleted");
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.signal_cellular_connected_no_internet_4_bar,
                  color: Colors.yellowAccent,
                ),
                title: const Text(
                  'Delete Slow Servers',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final removed = await _configManager.removeConfigs(
                    weak: true,
                  );
                  _showToast("$removed slow servers deleted");
                },
              ),
              ListTile(
                leading: const Icon(Icons.speed, color: Colors.blueAccent),
                title: const Text(
                  'Delete Untested Servers',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final removed = await _configManager.removeConfigs(
                    untestedSpeed: true,
                  );
                  _showToast("$removed untested servers deleted");
                },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.close, color: Colors.grey),
                title: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium,
                color: Colors.amber,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Free Plan',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.hasTime
                          ? '${(widget.remainingSeconds ~/ 3600)}h ${((widget.remainingSeconds % 3600) ~/ 60)}m remaining'
                          : 'No active plan',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: ScaleOnTap(
                      onTap: widget.onAddTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withValues(alpha: 0.5),
                              blurRadius: _glowAnimation.value + 4.0,
                              spreadRadius: _glowAnimation.value / 2,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_circle_fill,
                              size: 15,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '+1 Hour',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          // VIP Subscription Button linked to Telegram Support
          ScaleOnTap(
            onTap: () async {
              final tg = await ConfigGistService.getTelegramSupport();
              final url = Uri.parse('https://t.me/$tg');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: const [
                        Icon(Icons.workspace_premium_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Buy VIP Config',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Telegram',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

  // Grayscale matrix for disconnected state
  static const List<double> _grayscaleMatrix = [
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      0.65, 0,
  ];

  const _ConnectButton({
    required this.isConnected,
    required this.isConnecting,
    required this.onRefresh,
    required this.onConnect,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main Branded Circular Button
        Center(
          child: ScaleOnTap(
            onTap: onConnect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              width: 175,
              height: 175,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isConnected
                      ? [
                          const Color(0xFF0D9488),
                          const Color(0xFF10B981),
                        ] // Emerald Green
                      : (isConnecting
                          ? [
                              const Color(0xFFD97706),
                              const Color(0xFFF59E0B),
                            ] // Vibrant Amber
                          : [
                              const Color(0xFF262D3D),
                              const Color(0xFF161A22),
                            ]), // Metallic Gunmetal
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: isConnected
                      ? const Color(0xFF34D399)
                      : (isConnecting
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF3B4459)),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isConnected
                            ? const Color(0xFF10B981)
                            : (isConnecting
                                ? const Color(0xFFF59E0B)
                                : Colors.black))
                        .withValues(
                      alpha: isConnected || isConnecting ? 0.45 : 0.35,
                    ),
                    blurRadius: isConnected || isConnecting ? 28 : 14,
                    spreadRadius: isConnected || isConnecting ? 6 : 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: isConnected
                        ? Container(
                            key: const ValueKey('logo_connected'),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E676)
                                      .withValues(alpha: 0.5),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/icon.png',
                              width: 68,
                              height: 68,
                              fit: BoxFit.contain,
                            ),
                          )
                        : (isConnecting
                            ? Stack(
                                key: const ValueKey('logo_connecting'),
                                alignment: Alignment.center,
                                children: [
                                  const SizedBox(
                                    width: 76,
                                    height: 76,
                                    child: CircularProgressIndicator(
                                      color: Colors.amberAccent,
                                      strokeWidth: 3.5,
                                    ),
                                  ),
                                  Image.asset(
                                    'assets/icon.png',
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.contain,
                                  ),
                                ],
                              )
                            : ColorFiltered(
                                key: const ValueKey('logo_disconnected'),
                                colorFilter: const ColorFilter.matrix(
                                  _grayscaleMatrix,
                                ),
                                child: Image.asset(
                                  'assets/icon.png',
                                  width: 62,
                                  height: 62,
                                  fit: BoxFit.contain,
                                ),
                              )),
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      isConnected
                          ? 'CONNECTED'
                          : (isConnecting ? 'CONNECTING...' : 'CONNECT'),
                      key: ValueKey(
                        isConnected
                            ? 'CONNECTED'
                            : (isConnecting ? 'CONNECTING...' : 'CONNECT'),
                      ),
                      style: TextStyle(
                        color: isConnected
                            ? Colors.white
                            : (isConnecting
                                ? Colors.amberAccent
                                : Colors.grey.shade300),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Centered Glassmorphic Action Capsule (Refresh Configs & Skip)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF161A22).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleOnTap(
                onTap: onRefresh,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.refresh_rounded,
                      size: 17,
                      color: Colors.blueAccent,
                    ),
                    SizedBox(width: 6),
                    Text(
                      "Refresh Servers",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                height: 15,
                width: 1,
                color: Colors.white24,
              ),
              ScaleOnTap(
                onTap: onSkip,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.skip_next_rounded,
                      size: 17,
                      color: Colors.amberAccent,
                    ),
                    SizedBox(width: 6),
                    Text(
                      "Next Server",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
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

class _QuickConnectSuggestionCard extends StatelessWidget {
  final VpnConfigWithMetrics config;
  final VoidCallback onQuickConnect;

  const _QuickConnectSuggestionCard({
    required this.config,
    required this.onQuickConnect,
  });

  Color _getPingColor(int ping) {
    if (ping <= 0) return Colors.grey;
    if (ping <= 450) return const Color(0xFF00E676); // Excellent for Iran
    if (ping <= 1000) return const Color(0xFFFFB300); // Good / Fair
    return const Color(0xFFFF5252); // Poor (> 1000)
  }

  @override
  Widget build(BuildContext context) {
    final pingColor = _getPingColor(config.currentPing);
    return Padding(
      padding: const EdgeInsets.only(top: 14.0),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.blueAccent.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blueAccent.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.bolt,
                    color: Colors.amberAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Fast Server Found!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: pingColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: pingColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.speed, size: 14, color: pingColor),
                      const SizedBox(width: 4),
                      Text(
                        '${config.currentPing} ms',
                        style: TextStyle(
                          color: pingColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              config.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade300,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Connect immediately or wait for other servers to finish testing.',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            ScaleOnTap(
              onTap: onQuickConnect,
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.flash_on, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Quick Connect',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
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
}
