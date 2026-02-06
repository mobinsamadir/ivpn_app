import 'dart:math';
import '../services/config_manager.dart';

/// VPN Configuration with performance metrics
class VpnConfigWithMetrics {
  final String id;
  final String rawConfig;
  String name;
  final String? countryCode;
  bool isFavorite;
  final DateTime addedDate;
  Map<String, DeviceMetrics> deviceMetrics; // deviceId -> metrics
  
  VpnConfigWithMetrics({
    required this.id,
    required this.rawConfig,
    required this.name,
    this.countryCode,
    this.isFavorite = false,
    DateTime? addedDate,
    Map<String, DeviceMetrics>? deviceMetrics,
  })  : addedDate = addedDate ?? DateTime.now(),
        deviceMetrics = deviceMetrics ?? {};
  
  // Computed property getters (using current device ID)
  int get currentPing => _getPingForDevice(ConfigManager().currentDeviceId);

  double get currentSpeed => _getSpeedForDevice(ConfigManager().currentDeviceId);

  double get calculatedScore => _calculateScore(ConfigManager().currentDeviceId);

  double get successRate => _getSuccessRate(ConfigManager().currentDeviceId);

  // Private helper methods
  int _getPingForDevice(String deviceId) {
    return deviceMetrics[deviceId]?.latestPing ?? -1;
  }

  double _getSpeedForDevice(String deviceId) {
    return deviceMetrics[deviceId]?.latestSpeed ?? 0.0;
  }
  
  double _getSuccessRate(String deviceId) {
    final metrics = deviceMetrics[deviceId];
    if (metrics == null || metrics.usageCount == 0) return 0.0;
    return metrics.successfulConnections / metrics.usageCount;
  }

  double _calculateScore(String deviceId) {
    final metrics = deviceMetrics[deviceId];
    if (metrics == null) return 0.0;
    
    final pingScore = metrics.latestPing > 0 
        ? (1 / metrics.latestPing) * 1000 
        : 0;
    
    final speedScore = metrics.latestSpeed * 0.1;
    final stabilityScore = (metrics.usageCount > 0 ? metrics.successfulConnections / metrics.usageCount : 0.0) * 100;
    final usageScore = metrics.usageCount * 0.5;
    
    return (pingScore * 0.4) + 
           (speedScore * 0.3) + 
           (stabilityScore * 0.2) + 
           (min(usageScore, 10) * 0.1);
  }
  
  // Update metrics for a device
  void updateMetrics(String deviceId, {
    int? ping,
    double? speed,
    bool? success,
  }) {
    final metrics = deviceMetrics[deviceId] ?? DeviceMetrics();
    
    if (ping != null) {
      metrics.pingHistory.add(PingRecord(DateTime.now(), ping));
      metrics.latestPing = ping;
    }
    
    if (speed != null) {
      metrics.speedHistory.add(SpeedRecord(DateTime.now(), speed));
      metrics.latestSpeed = speed;
    }
    
    if (success != null) {
      metrics.usageCount++;
      if (success) {
        metrics.successfulConnections++;
      }
    }
    
    deviceMetrics[deviceId] = metrics;
  }
  

  
  // Check if config is validated for a device
  bool isValidated(String deviceId) {
    return _getPingForDevice(deviceId) > 0;
  }

  // Check if config is eligible for auto-test (doesn't have numbers in name)
  bool get isEligibleForAutoTest {
    return !name.contains(RegExp(r'[0-9]'));
  }
  
  // JSON serialization
  Map<String, dynamic> toJson() => {
    'id': id,
    'rawConfig': rawConfig,
    'name': name,
    'countryCode': countryCode,
    'isFavorite': isFavorite,
    'addedDate': addedDate.toIso8601String(),
    'deviceMetrics': deviceMetrics.map((k, v) => MapEntry(k, v.toJson())),
  };
  
  // Copy with method for creating updated instances
  VpnConfigWithMetrics copyWith({
    String? id,
    String? rawConfig,
    String? name,
    String? countryCode,
    bool? isFavorite,
    DateTime? addedDate,
    Map<String, DeviceMetrics>? deviceMetrics,
  }) {
    return VpnConfigWithMetrics(
      id: id ?? this.id,
      rawConfig: rawConfig ?? this.rawConfig,
      name: name ?? this.name,
      countryCode: countryCode ?? this.countryCode,
      isFavorite: isFavorite ?? this.isFavorite,
      addedDate: addedDate ?? this.addedDate,
      deviceMetrics: deviceMetrics ?? this.deviceMetrics,
    );
  }

  factory VpnConfigWithMetrics.fromJson(Map<String, dynamic> json) {
    return VpnConfigWithMetrics(
      id: json['id'],
      rawConfig: json['rawConfig'],
      name: json['name'],
      countryCode: json['countryCode'],
      isFavorite: json['isFavorite'] ?? false,
      addedDate: DateTime.parse(json['addedDate']),
      deviceMetrics: (json['deviceMetrics'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), DeviceMetrics.fromJson(Map<String, dynamic>.from(v))),
      ) ?? {},
    );
  }
}

class DeviceMetrics {
  List<PingRecord> pingHistory = [];
  List<SpeedRecord> speedHistory = [];
  int usageCount = 0;
  int successfulConnections = 0;
  int latestPing = -1;
  double latestSpeed = 0.0;
  
  DeviceMetrics();

  double get successRate => usageCount > 0 ? successfulConnections / usageCount : 0.0;

  Map<String, dynamic> toJson() => {
    'pingHistory': pingHistory.map((p) => p.toJson()).toList(),
    'speedHistory': speedHistory.map((s) => s.toJson()).toList(),
    'usageCount': usageCount,
    'successfulConnections': successfulConnections,
    'latestPing': latestPing,
    'latestSpeed': latestSpeed,
  };
  
  factory DeviceMetrics.fromJson(Map<String, dynamic> json) {
    final metrics = DeviceMetrics()
      ..usageCount = json['usageCount'] ?? 0
      ..successfulConnections = json['successfulConnections'] ?? 0
      ..latestPing = json['latestPing'] ?? -1
      ..latestSpeed = json['latestSpeed'] ?? 0.0;
    
    if (json['pingHistory'] != null) {
      metrics.pingHistory = (json['pingHistory'] as List)
          .map((p) => PingRecord.fromJson(p))
          .toList();
    }
    
    if (json['speedHistory'] != null) {
      metrics.speedHistory = (json['speedHistory'] as List)
          .map((s) => SpeedRecord.fromJson(s))
          .toList();
    }
    
    return metrics;
  }
}

class PingRecord {
  final DateTime timestamp;
  final int ping;
  final String networkType;
  
  PingRecord(this.timestamp, this.ping, [this.networkType = 'unknown']);
  
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'ping': ping,
    'networkType': networkType,
  };
  
  factory PingRecord.fromJson(Map<String, dynamic> json) {
    return PingRecord(
      DateTime.parse(json['timestamp']),
      json['ping'],
      json['networkType'] ?? 'unknown',
    );
  }
}

class SpeedRecord {
  final DateTime timestamp;
  final double downloadSpeed;
  final double uploadSpeed;
  
  SpeedRecord(this.timestamp, this.downloadSpeed, [this.uploadSpeed = 0.0]);
  
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'downloadSpeed': downloadSpeed,
    'uploadSpeed': uploadSpeed,
  };
  
  factory SpeedRecord.fromJson(Map<String, dynamic> json) {
    return SpeedRecord(
      DateTime.parse(json['timestamp']),
      json['downloadSpeed'] ?? 0.0,
      json['uploadSpeed'] ?? 0.0,
    );
  }
}

