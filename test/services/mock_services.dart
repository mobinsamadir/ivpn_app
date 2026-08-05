import 'package:mocktail/mocktail.dart';
import 'package:flutter/material.dart';
import 'package:ivpn_new/services/config_manager.dart';
import 'package:ivpn_new/services/native_vpn_service.dart';
import 'package:ivpn_new/services/funnel_service.dart';
import 'package:ivpn_new/services/testers/ephemeral_tester.dart';
import 'package:ivpn_new/services/ad_manager_service.dart';
import 'package:ivpn_new/services/connectivity_service.dart';
import 'package:ivpn_new/services/config_gist_service.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';
import 'dart:async';

class MockConfigManager extends Mock implements ConfigManager {
  @override
  bool get isConnected => false;
  @override
  String get connectionStatus => 'DISCONNECTED';
  @override
  List<VpnConfigWithMetrics> get allConfigs => [];
  @override
  List<VpnConfigWithMetrics> get historyConfigs => [];
  @override
  VpnConfigWithMetrics? get currentConfig => null;
  @override
  Future<void> loadConfigs() async {}
  @override
  bool get isAutoSwitchEnabled => false;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class MockNativeVpnService extends Mock implements NativeVpnService {
  @override
  Stream<String> get statusStream => const Stream.empty();
  @override
  Stream<String> get logStream => const Stream.empty();
  @override
  Stream<String> get connectionStatusStream => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> stopVpn() async {}
}

class MockFunnelService extends Mock implements FunnelService {
  @override
  Stream<String> get progressStream => const Stream.empty();
}

class MockEphemeralTester extends Mock implements EphemeralTester {}
class MockAdManagerService extends Mock implements AdManagerService {
  @override
  Future<void> initialize() async {}
  @override
  bool get isAdEnabled => false;
}

class MockConnectivityService extends Mock implements ConnectivityService {
  @override
  Stream<bool> get onConnectivityChanged => const Stream.empty();
  @override
  Future<bool> checkInternetAccess() async => true;
}
class MockConfigGistService extends Mock implements ConfigGistService {}
