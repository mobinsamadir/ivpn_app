import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../models/server_model.dart';
import '../services/native_vpn_service.dart';
import '../services/windows_vpn_service.dart';
import '../services/testers/ephemeral_tester.dart'; // ✅ Switched to EphemeralTester
import '../services/storage_service.dart';
import '../services/speed_test_service.dart';
import 'dart:io';
import '../utils/file_logger.dart';
import '../models/vpn_config_with_metrics.dart'; // Needed for EphemeralTester wrapper

enum ConnectionStatus { disconnected, connecting, connected, error }

class HomeProvider extends ChangeNotifier {
  String _logPath = "";
  String get logPath => _logPath;
  // --- Services ---
  final StorageService _storageService;
  final NativeVpnService _nativeVpnService;
  final WindowsVpnService _windowsVpnService;
  final SpeedTestService _speedTestService;
  final EphemeralTester _ephemeralTester = EphemeralTester(); // ✅

  // --- State ---
  bool _isLoading = true;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  Server? _connectedServer;
  List<Server> _servers = [];
  Server? _manualSelectedServer;
  List<Server> _recentServers = [];
  final Map<String, Timer> _pingTimers = {};
  List<String> _favoriteIds = [];
  List<String> _theBestIds = [];
  List<String> _obsoleteIds = [];
  bool _disposed = false;
  StreamSubscription? _statusSubscription;

  // --- Session Timer State ---
  Timer? _sessionTimer;
  Duration _remainingTime = Duration.zero;

  // --- A central timer to safely update the UI periodically ---
  Timer? _uiUpdateTimer;

  // --- Public Getters ---
  bool get isLoading => _isLoading;
  ConnectionStatus get connectionStatus => _connectionStatus;
  bool get isConnected => _connectionStatus == ConnectionStatus.connected;
  String get statusMessage {
    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        return "Connected to ${_connectedServer?.name ?? ''}";
      case ConnectionStatus.connecting:
        return "Connecting...";
      case ConnectionStatus.error:
        return "Connection Failed";
      default:
        return "Disconnected";
    }
  }

  Server? get manualSelectedServer => _manualSelectedServer;
  Server? get connectedServer => _connectedServer;
  List<Server> get recentServers => _recentServers;
  List<Server> get ivpnConfigs =>
      _servers.where((s) => s.type == ServerType.ivpn).toList();
  List<Server> get customConfigs =>
      _servers.where((s) => s.type == ServerType.custom).toList();
  List<Server> get favoriteServers =>
      _servers.where((s) => s.isFavorite).toList();
  List<Server> get theBestServers =>
      _servers.where((s) => _theBestIds.contains(s.id)).toList();
  List<Server> get obsoleteServers =>
      _servers.where((s) => _obsoleteIds.contains(s.id)).toList();

  Server? get bestPerformingServer {
    final onlineServers = _servers
        .where(
          (s) => s.status == PingStatus.good || s.status == PingStatus.medium,
        )
        .toList();
    if (onlineServers.isEmpty) return null;
    onlineServers.sort((a, b) => a.ping.compareTo(b.ping));
    return onlineServers.first;
  }

  Server? get serverToDisplay {
    if (_manualSelectedServer != null) return _manualSelectedServer;
    return bestPerformingServer;
  }

  // --- Session Timer Getters ---
  Duration get remainingTime => _remainingTime;
  String get formattedRemainingTime {
    final minutes = _remainingTime.inMinutes.remainder(60);
    final seconds = _remainingTime.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  HomeProvider({required StorageService storageService})
    : _storageService = storageService,
      _nativeVpnService = NativeVpnService(),
      _windowsVpnService = WindowsVpnService(),
      _speedTestService = SpeedTestService() {
    initializeApp();
  }

  @override
  void dispose() {
    _disposed = true;
    _uiUpdateTimer?.cancel();
    _statusSubscription?.cancel();
    _stopAllPinging();
    super.dispose();
  }

  Future<void> initializeApp() async {
    _servers = await _storageService.loadServers();
    _recentServers = await _storageService.loadRecentServers();
    _favoriteIds = await _storageService.loadFavoriteIds();
    _theBestIds = await _storageService.loadTheBestIds();
    _obsoleteIds = await _storageService.loadObsoleteIds();
    _enrichServersWithMetadata();

    _listenToConnectionStatus();

    _logPath = await FileLogger.getLogPath();
    
    _isLoading = false;
    _startPingingAllServers();

    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      notifyListeners();
    });
  }

  void _listenToConnectionStatus() {
    if (Platform.isWindows) {
      _statusSubscription = _windowsVpnService.statusStream.listen((status) {
        _handleStatusChange(status);
      });
    } else {
      _statusSubscription = _nativeVpnService.connectionStatusStream.listen((status) {
        _handleStatusChange(status);
      });
    }
  }

  void _handleStatusChange(dynamic status) {
    switch (status) {
      case "CONNECTED":
        _connectionStatus = ConnectionStatus.connected;
        break;
      case "CONNECTING":
        _connectionStatus = ConnectionStatus.connecting;
        break;
      case "DISCONNECTED":
        _connectionStatus = ConnectionStatus.disconnected;
        _connectedServer = null;
        break;
      case "ERROR":
        _connectionStatus = ConnectionStatus.error;
        _connectedServer = null;
        break;
      default:
        break;
    }
    notifyListeners();
  }

  Future<void> _executePing(Server server) async {
    if (!_pingTimers.containsKey(server.id) || _disposed) return;

    int ping;
    if (Platform.isWindows) {
      // Use EphemeralTester logic for robust testing
      final tempConfig = VpnConfigWithMetrics(
          id: server.id,
          rawConfig: server.rawConfig,
          name: server.name
      );
      final result = await _ephemeralTester.runTest(tempConfig);
      ping = result.currentPing;
    } else {
      ping = await _nativeVpnService.getPing(server.rawConfig);
    }

    PingStatus newStatus;
    if (ping > 0 && ping < 700) {
      newStatus = PingStatus.good;
    } else if (ping > 0)
      newStatus = PingStatus.medium;
    else
      newStatus = PingStatus.bad;

    _updateServerStateInMemory(
      serverId: server.id,
      ping: ping,
      status: newStatus,
    );
    _manageSpecialLists(server.id, ping, newStatus);

    final nextPingDelay = isConnected
        ? const Duration(seconds: 5)
        : const Duration(seconds: 30);
    _schedulePing(server, initialDelay: nextPingDelay);
  }

  Future<void> handleConnection() async {
    if (_connectionStatus == ConnectionStatus.connecting) return;

    if (isConnected) {
      await stopVpn();
    } else {
      final targetServer = serverToDisplay;
      if (targetServer != null) {
        _connectedServer = targetServer;
        notifyListeners();

        if (Platform.isWindows) {
          try {
            await _windowsVpnService.startVpn(targetServer.rawConfig.trim());
          } catch (e) {
            print("Error starting Windows VPN: $e");
          }
        } else {
          await _nativeVpnService.connect(targetServer.rawConfig);
        }
        _addServerToRecents(targetServer);

        startSession();
      }
    }

  }

  // --- Session Timer Methods ---
  void startSession() {
    stopSession();
    _remainingTime = const Duration(hours: 1);
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _remainingTime = _remainingTime - const Duration(seconds: 1);
      if (_remainingTime.isNegative) {
        _remainingTime = Duration.zero;
        stopVpn();
        _showSessionExpiredNotification();
        timer.cancel();
      }
      notifyListeners();
    });
  }

  void stopSession() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _remainingTime = Duration.zero;
    notifyListeners();
  }

  void _showSessionExpiredNotification() {
    print('Session expired. Please reconnect.');
  }

  Future<void> stopVpn() async {
    stopSession();
    if (Platform.isWindows) {
      await _windowsVpnService.stopVpn();
    } else {
      await _nativeVpnService.disconnect();
    }
  }

  Future<void> toggleFavorite(Server server) async {
    final isCurrentlyFavorite = _favoriteIds.contains(server.id);
    if (isCurrentlyFavorite) {
      _favoriteIds.remove(server.id);
    } else {
      _favoriteIds.add(server.id);
    }
    await _storageService.saveFavoriteIds(_favoriteIds);
    _updateServerStateInMemory(
      serverId: server.id,
      isFavorite: !isCurrentlyFavorite,
    );
    notifyListeners();
  }

  Future<void> handleSpeedTest(Server server) async {
    if (server.isTestingSpeed) return;
    _updateServerStateInMemory(serverId: server.id, isTestingSpeed: true);
    notifyListeners();

    final speed = await _speedTestService.testDownloadSpeed();

    _updateServerStateInMemory(
      serverId: server.id,
      downloadSpeed: speed,
      isTestingSpeed: false,
    );
  }

  void _updateServerStateInMemory({
    required String serverId,
    int? ping,
    PingStatus? status,
    bool? isFavorite,
    double? downloadSpeed,
    bool? isTestingSpeed,
  }) {
    final index = _servers.indexWhere((s) => s.id == serverId);
    if (index != -1) {
      _servers[index] = _servers[index].copyWith(
        ping: ping,
        status: status,
        isFavorite: isFavorite,
        downloadSpeed: downloadSpeed,
        isTestingSpeed: isTestingSpeed,
      );
    }
  }

  void _enrichServersWithMetadata() {
    _servers = _servers.map((server) {
      return server.copyWith(isFavorite: _favoriteIds.contains(server.id));
    }).toList();
  }

  Future<void> loadServersFromUrl() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    final url = Uri.parse(
      'https://raw.githubusercontent.com/mobinsamadir/ivpn-servers/main/servers.txt',
    );
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final lines = utf8.decode(response.bodyBytes).split('\n');
        final networkServers = lines
            .map(
              (l) => Server.fromConfigString(l.trim(), type: ServerType.ivpn),
            )
            .whereType<Server>()
            .toList();
        if (networkServers.isNotEmpty) {
          _stopAllPinging();
          _servers.removeWhere((s) => s.type == ServerType.ivpn);
          _servers.addAll(networkServers);
          await _storageService.saveServers(_servers);
          await _storageService.saveLastUpdateTimestamp();
          _enrichServersWithMetadata();
          _startPingingAllServers();
        }
      }
    } catch (e) {
      // Handle error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addServersFromUserInput(String userInput) async {
    int addedCount = 0;
    if (userInput.trim().startsWith('http')) {
      _isLoading = true;
      notifyListeners();
      addedCount = await _loadServersFromSubscription(userInput);
      _isLoading = false;
    } else {
      final configs = userInput
          .split('\n')
          .where((line) => line.trim().isNotEmpty);
      for (final config in configs) {
        final newServer = Server.fromConfigString(
          config,
          type: ServerType.custom,
        );
        if (newServer != null && !_servers.any((s) => s.id == newServer.id)) {
          _servers.insert(0, newServer);
          _schedulePing(newServer);
          addedCount++;
        }
      }
    }
    if (addedCount > 0) {
      await _storageService.saveServers(_servers);
      _enrichServersWithMetadata();
    }
    notifyListeners();
  }

  Future<int> _loadServersFromSubscription(String subUrl) async {
    int addedCount = 0;
    try {
      final response = await http.get(Uri.parse(subUrl));
      if (response.statusCode == 200) {
        String decodedContent;
        try {
          decodedContent = utf8.decode(base64Decode(response.body));
        } catch (e) {
          decodedContent = response.body;
        }
        final configs = decodedContent
            .split('\n')
            .where((line) => line.trim().isNotEmpty);
        for (final config in configs) {
          final newServer = Server.fromConfigString(
            config,
            type: ServerType.custom,
          );
          if (newServer != null && !_servers.any((s) => s.id == newServer.id)) {
            _servers.add(newServer);
            _schedulePing(newServer);
            addedCount++;
          }
        }
      }
    } catch (e) {
      print("Error loading subscription: $e");
    }
    return addedCount;
  }

  void _startPingingAllServers() {
    _stopAllPinging();
    final List<Server> pingingOrder = [];
    final Set<String> addedIds = {};
    void addToList(List<Server> list) {
      for (var server in list) {
        if (!addedIds.contains(server.id)) {
          pingingOrder.add(server);
          addedIds.add(server.id);
        }
      }
    }

    addToList(favoriteServers);
    addToList(theBestServers);
    addToList(obsoleteServers);
    addToList(_servers);
    for (int i = 0; i < pingingOrder.length; i++) {
      _schedulePing(
        pingingOrder[i],
        isInitial: true,
        initialDelay: Duration(milliseconds: i * 100),
      );
    }
  }

  void _stopAllPinging() {
    _pingTimers.forEach((_, timer) => timer.cancel());
    _pingTimers.clear();
  }

  void _schedulePing(
    Server server, {
    bool isInitial = false,
    Duration? initialDelay,
  }) {
    _pingTimers[server.id]?.cancel();
    final delay =
        initialDelay ??
        (isInitial
            ? Duration(milliseconds: _servers.indexOf(server) * 100)
            : Duration.zero);
    _pingTimers[server.id] = Timer(delay, () => _executePing(server));
  }

  Future<void> cleanupServers({required bool removeSlow}) async {
    _servers.removeWhere(
      (s) => removeSlow
          ? (s.status != PingStatus.good)
          : (s.status == PingStatus.bad),
    );
    await _storageService.saveServers(_servers);
    notifyListeners();
  }

  Future<void> deleteServer(Server server) async {
    _stopPingForServer(server);
    _servers.removeWhere((s) => s.id == server.id);
    _favoriteIds.remove(server.id);
    _theBestIds.remove(server.id);
    _obsoleteIds.remove(server.id);
    _recentServers.removeWhere((s) => s.id == server.id);
    await _storageService.saveServers(_servers);
    await _storageService.saveFavoriteIds(_favoriteIds);
    await _storageService.saveTheBestIds(_theBestIds);
    await _storageService.saveObsoleteIds(_obsoleteIds);
    await _storageService.saveRecentServers(_recentServers);
    notifyListeners();
  }

  void selectServer(Server? server) {
    _manualSelectedServer = server;
    notifyListeners();
  }

  void _addServerToRecents(Server server) {
    _recentServers.removeWhere((s) => s.id == server.id);
    _recentServers.insert(0, server);
    if (_recentServers.length > 5) {
      _recentServers = _recentServers.sublist(0, 5);
    }
    _storageService.saveRecentServers(_recentServers);
  }

  void _manageSpecialLists(String serverId, int ping, PingStatus newStatus) {
    bool listsChanged = false;
    if (_theBestIds.contains(serverId) && newStatus == PingStatus.bad) {
      _theBestIds.remove(serverId);
      if (!_obsoleteIds.contains(serverId)) {
        _obsoleteIds.add(serverId);
      }
      listsChanged = true;
    }
    if (newStatus == PingStatus.good &&
        ping < 150 &&
        !_theBestIds.contains(serverId) &&
        !_obsoleteIds.contains(serverId)) {
      _theBestIds.add(serverId);
      listsChanged = true;
    }
    if (listsChanged) {
      _storageService.saveTheBestIds(_theBestIds);
      _storageService.saveObsoleteIds(_obsoleteIds);
    }
  }

  void _stopPingForServer(Server server) {
    _pingTimers[server.id]?.cancel();
    _pingTimers.remove(server.id);
  }
}
