import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/advanced_logger.dart';

class TimeWalletService extends ChangeNotifier {
  static final TimeWalletService _instance = TimeWalletService._internal();
  factory TimeWalletService() => _instance;
  TimeWalletService._internal();

  static const String _storageKey = "wallet_expire_timestamp";
  static const int rewardDurationSeconds = 3600; // 1 Hour

  DateTime? _networkTimeAtSync;
  final Stopwatch _sessionStopwatch = Stopwatch();
  int _expireTimestampMs = 0; // Epoch milliseconds based on network time
  Timer? _countdownTimer;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _expireTimestampMs = prefs.getInt(_storageKey) ?? 0;

      await syncNetworkTime();
      _startCountdown();
      _isInitialized = true;
    } catch (e) {
      AdvancedLogger.error("[TimeWallet] Initialization failed: \$e");
    }
  }

  /// Fetch true network time to prevent local clock cheating
  Future<void> syncNetworkTime() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final request = await client.getUrl(Uri.parse('https://google.com/generate_204'));
      final response = await request.close();

      final dateHeader = response.headers.value('date');
      if (dateHeader != null) {
        _networkTimeAtSync = HttpDate.parse(dateHeader);
        _sessionStopwatch.reset();
        _sessionStopwatch.start();
        AdvancedLogger.info("[TimeWallet] Network time synced: \$_networkTimeAtSync");
      } else {
        throw Exception("Missing Date header");
      }
    } catch (e) {
      AdvancedLogger.warn("[TimeWallet] Failed to fetch network time: \$e. Falling back to local clock.");
      _networkTimeAtSync = DateTime.now().toUtc();
      _sessionStopwatch.reset();
      _sessionStopwatch.start();
    }
  }

  /// Get the current, un-cheatable time
  DateTime get currentSecureTime {
    if (_networkTimeAtSync == null) {
      return DateTime.now().toUtc(); // Fallback
    }
    return _networkTimeAtSync!.add(_sessionStopwatch.elapsed);
  }

  /// Remaining seconds. If < 0, returns 0.
  int get remainingSeconds {
    if (_expireTimestampMs <= 0) return 0;

    final int nowMs = currentSecureTime.millisecondsSinceEpoch;
    final int diff = _expireTimestampMs - nowMs;

    return diff > 0 ? diff ~/ 1000 : 0;
  }

  bool get hasTime => remainingSeconds > 0;

  /// Add time to wallet (e.g., after watching an ad)
  Future<void> rewardTime() async {
    // Re-sync network time before granting reward to ensure accuracy
    await syncNetworkTime();

    final int nowMs = currentSecureTime.millisecondsSinceEpoch;

    if (_expireTimestampMs < nowMs) {
      // Wallet expired, start from now
      _expireTimestampMs = nowMs + (rewardDurationSeconds * 1000);
    } else {
      // Wallet still has time, add to it
      _expireTimestampMs += (rewardDurationSeconds * 1000);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageKey, _expireTimestampMs);

    AdvancedLogger.info("[TimeWallet] Time rewarded. New expiry: \${DateTime.fromMillisecondsSinceEpoch(_expireTimestampMs)}");
    notifyListeners();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!hasTime && _expireTimestampMs > 0) {
        _expireTimestampMs = 0; // Reset
        AdvancedLogger.warn("[TimeWallet] Time expired!");
        notifyListeners();
      } else if (hasTime) {
        notifyListeners(); // Notify every second for UI updates
      }
    });
  }

  /// Method to consume time for testing/debugging
  @visibleForTesting
  Future<void> consumeTime(int seconds) async {
    _expireTimestampMs -= (seconds * 1000);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageKey, _expireTimestampMs);
    notifyListeners();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _sessionStopwatch.stop();
    super.dispose();
  }
}
