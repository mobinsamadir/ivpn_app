import 'package:ivpn_new/models/vpn_config.dart';

class DeviceMetrics {
  final int latestPing;
  final double latestSpeed;
  final DateTime lastUpdated;

  DeviceMetrics({
    required this.latestPing,
    required this.latestSpeed,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'latestPing': latestPing,
    'latestSpeed': latestSpeed,
    'lastUpdated': lastUpdated.toIso8601String(),
  };

  factory DeviceMetrics.fromJson(Map<String, dynamic> json) {
    return DeviceMetrics(
      latestPing: json['latestPing'] as int? ?? -1,
      latestSpeed: (json['latestSpeed'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
    );
  }
}

class VpnConfigWithMetrics {
  final String id;
  final VpnConfig rawConfig;
  final String name;
  final String? countryCode;
  final bool isFavorite;
  final DateTime addedDate;
  final Map<String, DeviceMetrics> deviceMetrics;

  // New fields for advanced server testing
  final int failureCount;
  final int lastSuccessfulConnectionTime;
  final bool isAlive;
  final int tier; // 0=Untested, 1=Alive, 2=LowLatency, 3=Stable/HighSpeed

  VpnConfigWithMetrics({
    required this.id,
    required this.rawConfig,
    required this.name,
    this.countryCode,
    this.isFavorite = false,
    DateTime? addedDate,
    Map<String, DeviceMetrics>? deviceMetrics,
    this.failureCount = 0,
    this.lastSuccessfulConnectionTime = 0,
    this.isAlive = true,
    this.tier = 0,
  })  : addedDate = addedDate ?? DateTime.now(),
        deviceMetrics = deviceMetrics ?? {};

  // Computed properties
  int get currentPing {
     // Use a default key or inject device ID logic here. For simplicity, we use the raw map.
     // In real app, pass ConfigManager().currentDeviceId
     if (deviceMetrics.isEmpty) return -1;
     return deviceMetrics.values.first.latestPing; 
  }

  // Advanced Score
  double get score {
    double score = 100.0;
    score -= (failureCount * 20);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastSuccessfulConnectionTime < 86400000) score += 50;
    if (currentPing > 0) score -= (currentPing / 20);
    if (!isAlive) score = -1000;
    return score;
  }

  VpnConfigWithMetrics copyWith({
    String? id,
    VpnConfig? rawConfig,
    String? name,
    String? countryCode,
    bool? isFavorite,
    DateTime? addedDate,
    Map<String, DeviceMetrics>? deviceMetrics,
    int? failureCount,
    int? lastSuccessfulConnectionTime,
    bool? isAlive,
    int? tier,
  }) {
    return VpnConfigWithMetrics(
      id: id ?? this.id,
      rawConfig: rawConfig ?? this.rawConfig,
      name: name ?? this.name,
      countryCode: countryCode ?? this.countryCode,
      isFavorite: isFavorite ?? this.isFavorite,
      addedDate: addedDate ?? this.addedDate,
      deviceMetrics: deviceMetrics ?? this.deviceMetrics,
      failureCount: failureCount ?? this.failureCount,
      lastSuccessfulConnectionTime: lastSuccessfulConnectionTime ?? this.lastSuccessfulConnectionTime,
      isAlive: isAlive ?? this.isAlive,
      tier: tier ?? this.tier,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'rawConfig': rawConfig.toJson(),
    'name': name,
    'countryCode': countryCode,
    'isFavorite': isFavorite,
    'addedDate': addedDate.toIso8601String(),
    'deviceMetrics': deviceMetrics.map((k, v) => MapEntry(k, v.toJson())),
    'failureCount': failureCount,
    'lastSuccessfulConnectionTime': lastSuccessfulConnectionTime,
    'isAlive': isAlive,
    'tier': tier,
  };

  factory VpnConfigWithMetrics.fromJson(Map<String, dynamic> json) {
    return VpnConfigWithMetrics(
      id: json['id'] as String,
      rawConfig: VpnConfig.fromJson(json['rawConfig'] as Map<String, dynamic>),
      name: json['name'] as String,
      countryCode: json['countryCode'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      addedDate: DateTime.parse(json['addedDate'] as String),
      deviceMetrics: (json['deviceMetrics'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, DeviceMetrics.fromJson(v as Map<String, dynamic>)),
      ) ?? {},
      failureCount: json['failureCount'] as int? ?? 0,
      lastSuccessfulConnectionTime: json['lastSuccessfulConnectionTime'] as int? ?? 0,
      isAlive: json['isAlive'] as bool? ?? true,
      tier: json['tier'] as int? ?? 0,
    );
  }
}