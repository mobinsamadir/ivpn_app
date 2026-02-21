import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/advanced_logger.dart';

class AccessManager extends ChangeNotifier {
  static final AccessManager _instance = AccessManager._internal();
  factory AccessManager() => _instance;
  AccessManager._internal();

  static const String _prefsKey = 'vpn_access_expiration';
  DateTime? _expirationDate;

  // Getters
  DateTime? get expirationDate => _expirationDate;
  
  bool get hasAccess {
    if (_expirationDate == null) return false;
    return _expirationDate!.isAfter(DateTime.now());
  }

  Duration get remainingTime {
    if (_expirationDate == null) return Duration.zero;
    final now = DateTime.now();
    if (_expirationDate!.isBefore(now)) return Duration.zero;
    return _expirationDate!.difference(now);
  }

  // Initialization
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expirationTs = prefs.getInt(_prefsKey);
      
      if (expirationTs != null) {
        _expirationDate = DateTime.fromMillisecondsSinceEpoch(expirationTs);
        AdvancedLogger.info("🕒 [AccessManager] Loaded expiration: $_expirationDate");
      } else {
        AdvancedLogger.info("🕒 [AccessManager] No active plan found.");
      }
      notifyListeners();
    } catch (e) {
      AdvancedLogger.error("❌ [AccessManager] Init error: $e");
    }
  }

  // Add Time (Rewards)
  Future<void> addTime(Duration duration) async {
    final now = DateTime.now();
    
    if (_expirationDate == null || _expirationDate!.isBefore(now)) {
      _expirationDate = now.add(duration);
    } else {
      _expirationDate = _expirationDate!.add(duration);
    }
    
    await _save();
    notifyListeners();
    AdvancedLogger.info("🎁 [AccessManager] Time added! New expiry: $_expirationDate");
  }

  // Internal Save
  Future<void> _save() async {
    if (_expirationDate != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, _expirationDate!.millisecondsSinceEpoch);
    }
  }

  // Force Clear (Debug/Testing)
  Future<void> clearAccess() async {
    _expirationDate = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }
}
