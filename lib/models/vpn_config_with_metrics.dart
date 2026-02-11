
class DeviceMetrics {
  final int latestPing;
  final double latestSpeed;
  final DateTime lastUpdated;
  final int usageCount;

  DeviceMetrics({
    required this.latestPing,
    required this.latestSpeed,
    required this.lastUpdated,
    this.usageCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'latestPing': latestPing,
    'latestSpeed': latestSpeed,
    'lastUpdated': lastUpdated.toIso8601String(),
    'usageCount': usageCount,
  };

  factory DeviceMetrics.fromJson(Map<String, dynamic> json) {
    return DeviceMetrics(
      latestPing: json['latestPing'] as int? ?? -1,
      latestSpeed: (json['latestSpeed'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      usageCount: json['usageCount'] as int? ?? 0,
    );
  }
}

class TestResult {
  final bool success;
  final int latency;
  final String? error;

  TestResult({required this.success, this.latency = 0, this.error});

  Map<String, dynamic> toJson() => {
    'success': success,
    'latency': latency,
    'error': error,
  };

  factory TestResult.fromJson(Map<String, dynamic> json) {
    return TestResult(
      success: json['success'] as bool? ?? false,
      latency: json['latency'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }
}

class VpnConfigWithMetrics {
  final String id;
  final String rawConfig;
  final String name;
  final String? countryCode;
  final bool isFavorite;
  final DateTime addedDate;
  final Map<String, DeviceMetrics> deviceMetrics;

  // Advanced server testing fields
  final int failureCount;
  final int lastSuccessfulConnectionTime;
  final bool isAlive;
  final int tier; // 0=Untested, 1=Alive, 2=LowLatency, 3=Stable/HighSpeed

  // Pipeline Tester Fields
  final Map<String, TestResult> stageResults;
  final String? lastFailedStage;
  final String? failureReason;
  final DateTime? lastTestedAt;

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
    Map<String, TestResult>? stageResults,
    this.lastFailedStage,
    this.failureReason,
    this.lastTestedAt,
  })  : addedDate = addedDate ?? DateTime.now(),
        deviceMetrics = deviceMetrics ?? {},
        stageResults = stageResults ?? {};

  // Computed properties
  int get currentPing {
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
    if (lastFailedStage != null) score -= 500;
    return score;
  }

  double get calculatedScore => score;

  double get currentSpeed {
    if (deviceMetrics.isEmpty) return 0.0;
    return deviceMetrics.values.first.latestSpeed;
  }

  double get successRate {
    return 0.0; // Placeholder
  }

  // Helper to check if config is dead
  bool get isDead => lastFailedStage != null;

  VpnConfigWithMetrics updateMetrics({
    required String deviceId,
    int? ping,
    double? speed,
    bool connectionSuccess = false,
  }) {
    final currentMetrics = deviceMetrics[deviceId] ?? 
        DeviceMetrics(
          latestPing: -1, 
          latestSpeed: 0.0, 
          lastUpdated: DateTime.now(),
          usageCount: 0,
        );
    
    final updatedMetrics = DeviceMetrics(
      latestPing: ping ?? currentMetrics.latestPing,
      latestSpeed: speed ?? currentMetrics.latestSpeed,
      lastUpdated: DateTime.now(),
      usageCount: currentMetrics.usageCount + (connectionSuccess ? 1 : 0),
    );

    final newDeviceMetrics = Map<String, DeviceMetrics>.from(deviceMetrics);
    newDeviceMetrics[deviceId] = updatedMetrics;

    return copyWith(deviceMetrics: newDeviceMetrics);
  }

  bool get isValidated {
    return (currentPing > 0 && currentPing < 2000) || lastSuccessfulConnectionTime > 0;
  }

  bool get isEligibleForAutoTest {
    return isAlive && failureCount < 5;
  }

  VpnConfigWithMetrics copyWith({
    String? id,
    String? rawConfig,
    String? name,
    String? countryCode,
    bool? isFavorite,
    DateTime? addedDate,
    Map<String, DeviceMetrics>? deviceMetrics,
    int? failureCount,
    int? lastSuccessfulConnectionTime,
    bool? isAlive,
    int? tier,
    Map<String, TestResult>? stageResults,
    String? lastFailedStage,
    String? failureReason,
    DateTime? lastTestedAt,
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
      stageResults: stageResults ?? this.stageResults,
      lastFailedStage: lastFailedStage ?? this.lastFailedStage,
      failureReason: failureReason ?? this.failureReason,
      lastTestedAt: lastTestedAt ?? this.lastTestedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'rawConfig': rawConfig,
    'name': name,
    'countryCode': countryCode,
    'isFavorite': isFavorite,
    'addedDate': addedDate.toIso8601String(),
    'deviceMetrics': deviceMetrics.map((k, v) => MapEntry<String, dynamic>(k, v.toJson())),
    'failureCount': failureCount,
    'lastSuccessfulConnectionTime': lastSuccessfulConnectionTime,
    'isAlive': isAlive,
    'tier': tier,
    'stageResults': stageResults.map((k, v) => MapEntry<String, dynamic>(k, v.toJson())),
    'lastFailedStage': lastFailedStage,
    'failureReason': failureReason,
    'lastTestedAt': lastTestedAt?.toIso8601String(),
  };

  factory VpnConfigWithMetrics.fromJson(Map<String, dynamic> json) {
    return VpnConfigWithMetrics(
      id: json['id'] as String,
      rawConfig: json['rawConfig'] as String,
      name: json['name'] as String,
      countryCode: json['countryCode'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      addedDate: DateTime.parse(json['addedDate'] as String),
      deviceMetrics: (json['deviceMetrics'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry<String, DeviceMetrics>(k, DeviceMetrics.fromJson(v as Map<String, dynamic>)),
      ) ?? {},
      failureCount: json['failureCount'] as int? ?? 0,
      lastSuccessfulConnectionTime: json['lastSuccessfulConnectionTime'] as int? ?? 0,
      isAlive: json['isAlive'] as bool? ?? true,
      tier: json['tier'] as int? ?? 0,
      stageResults: (json['stageResults'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry<String, TestResult>(k, TestResult.fromJson(v as Map<String, dynamic>)),
      ) ?? {},
      lastFailedStage: json['lastFailedStage'] as String?,
      failureReason: json['failureReason'] as String?,
      lastTestedAt: json['lastTestedAt'] != null ? DateTime.parse(json['lastTestedAt'] as String) : null,
    );
  }
}
