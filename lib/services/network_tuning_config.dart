import 'dart:convert';
import 'package:flutter/services.dart';
import '../utils/advanced_logger.dart';

/// Centralized network timing configuration driven by `assets/version.json`.
///
/// All timeouts and delays throughout the app are computed by multiplying a
/// base value with [multiplier] (`network_tolerance_multiplier`).
///
/// **Default multiplier: 1.5** — suitable for moderately censored networks
/// such as Iran (DPI, throttling, etc.).  A value of `1.0` means standard
/// open-internet timing; `2.0`–`3.0` is for severe disruption.
///
/// The singleton is refreshed automatically whenever `ConfigManager` fetches
/// a fresh remote `version.json`.
class NetworkTuningConfig {
  NetworkTuningConfig._internal();
  static final NetworkTuningConfig _instance = NetworkTuningConfig._internal();

  /// Singleton accessor.
  static NetworkTuningConfig get instance => _instance;

  // ---------- raw base values (before multiplication) ----------
  static const double _baseTcpPingMs = 2500;
  static const double _baseProxySpawnCooldownMs = 300;
  static const double _baseSocketReadyPollTimeoutMs = 2500;
  static const double _basePostSocketReadyWarmupMs = 350;
  static const double _baseHttpProbeTimeoutMs = 6500;
  static const double _baseWatchdogConnectivityMs = 18000;
  static const double _baseWatchdogSpeedMs = 30000;
  static const double _basePreFlightTimeoutMs = 20000;
  static const double _baseConnectWaitTimeoutSec = 20;
  static const double _baseStage1TcpTimeoutMs = 5000;

  // ---------- mutable state ----------
  double _multiplier = 1.5;
  int _httpProbeRetries = 3; // base value; increases with multiplier

  /// The current tolerance multiplier loaded from `version.json`.
  double get multiplier => _multiplier;

  // ---------- computed timing getters ----------

  /// TCP ping timeout for Stage-1 funnel check (ms).
  int get tcpPingTimeoutMs => (_baseTcpPingMs * _multiplier).round();

  /// Delay between spawning test-proxy and starting port-ready poll (ms).
  int get proxySpawnCooldownMs => (_baseProxySpawnCooldownMs * _multiplier).round();

  /// Maximum time to poll for the local HTTP proxy port to become ready (ms).
  int get socketReadyPollTimeoutMs => (_baseSocketReadyPollTimeoutMs * _multiplier).round();

  /// Warm-up delay *after* port is ready, before sending the first HTTP probe (ms).
  int get postSocketReadyWarmupMs => (_basePostSocketReadyWarmupMs * _multiplier).round();

  /// Per-attempt timeout for the HTTP 204-probe (ms).
  int get httpProbeTimeoutMs => (_baseHttpProbeTimeoutMs * _multiplier).round();

  /// Number of HTTP probe retry attempts (min 2, scales with multiplier).
  int get httpProbeRetries => _httpProbeRetries;

  /// Watchdog timeout for connectivity (Stage-1/2) tests (ms).
  int get watchdogConnectivityMs => (_baseWatchdogConnectivityMs * _multiplier).round();

  /// Watchdog timeout for speed (Stage-3) tests (ms).
  int get watchdogSpeedMs => (_baseWatchdogSpeedMs * _multiplier).round();

  /// Pre-flight verification timeout (ms).
  int get preFlightTimeoutMs => (_basePreFlightTimeoutMs * _multiplier).round();

  /// Wait for `CONNECTED` state from native service (seconds).
  int get connectWaitTimeoutSec => (_baseConnectWaitTimeoutSec * _multiplier).round();

  /// Stage-1 TCP direct-connect timeout (ms).
  int get stage1TcpTimeoutMs => (_baseStage1TcpTimeoutMs * _multiplier).round();

  // ---------- initialisation ----------

  /// Load timing configuration from the bundled `assets/version.json`.
  ///
  /// Should be called once during app startup (before any testing begins).
  /// Call [refresh] to update values after downloading a fresh remote config.
  Future<void> init() async {
    try {
      final raw = await rootBundle.loadString('assets/version.json');
      _applyJson(raw);
      AdvancedLogger.info(
        '[NetworkTuning] Loaded from asset. multiplier=$_multiplier, '
        'tcpPing=${tcpPingTimeoutMs}ms, httpProbe=${httpProbeTimeoutMs}ms, '
        'retries=$httpProbeRetries',
      );
    } catch (e) {
      AdvancedLogger.warn('[NetworkTuning] Could not load from asset, using defaults. $e');
    }
  }

  /// Apply a freshly downloaded `version.json` string (from remote fetch).
  ///
  /// This allows hot-updating timing without an app restart.
  void refresh(String versionJsonString) {
    try {
      _applyJson(versionJsonString);
      AdvancedLogger.info(
        '[NetworkTuning] Refreshed from remote. multiplier=$_multiplier',
      );
    } catch (e) {
      AdvancedLogger.warn('[NetworkTuning] Failed to refresh from remote: $e');
    }
  }

  void _applyJson(String jsonStr) {
    final Map<String, dynamic> data =
        jsonDecode(jsonStr) as Map<String, dynamic>;

    // Primary multiplier
    if (data['network_tolerance_multiplier'] != null) {
      final raw = data['network_tolerance_multiplier'];
      _multiplier = (raw is num ? raw.toDouble() : double.tryParse(raw.toString()) ?? 1.5)
          .clamp(0.5, 5.0);
    }

    // Optional granular base-value overrides inside `network_tuning` block
    if (data['network_tuning'] is Map) {
      // (future-proof: these can override individual base values at runtime)
    }

    // Derived: retries scale with multiplier
    _httpProbeRetries = (_multiplier >= 2.0) ? 4 : (_multiplier >= 1.5 ? 3 : 2);
  }
}
