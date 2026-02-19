
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

class VpnConfigWithMetrics implements Comparable<VpnConfigWithMetrics> {
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

  final int ping;

  // Funnel & Score Fields
  final int funnelStage; // 0=Untested, 1=TCP, 2=HTTP, 3=Speed
  final int speedScore;  // 0-100

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
    this.ping = -1,
    this.funnelStage = 0,
    this.speedScore = 0,
    Map<String, TestResult>? stageResults,
    this.lastFailedStage,
    this.failureReason,
    this.lastTestedAt,
  })  : addedDate = addedDate ?? DateTime.now(),
        deviceMetrics = deviceMetrics ?? {},
        stageResults = stageResults ?? {};

  // Computed properties
  int get currentPing {
     if (ping != -1) return ping;
     if (deviceMetrics.isEmpty) return -1;
     return deviceMetrics.values.first.latestPing; 
  }

  // Legacy Score (Deprecated usage but kept for backward compat if needed)
  double get score {
    // 1. Funnel Stage (0-3) - Biggest Factor (1000 points per stage)
    double baseScore = funnelStage * 1000.0;

    // 2. Speed Score (0-50) - (10 points per unit)
    baseScore += speedScore * 10.0;

    // 3. Ping Bonus
    if (currentPing > 0) {
      baseScore += (2000 - currentPing) / 10.0; // Lower ping gives slightly more points
    } else {
      // 4. PURGATORY BONUS: Not Verified (-1 Ping), but has History
      if (lastSuccessfulConnectionTime > 0) {
         baseScore += 100.0; // Rank above purely random/dead configs
      }
    }

    // 5. Favorite Override
    if (isFavorite) baseScore += 5000;

    // 6. Failure Penalty
    baseScore -= (failureCount * 50);

    return baseScore;
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
  bool get isDead => failureCount >= 3;

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
    return funnelStage >= 2; // Passed HTTP Stage
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
    int? ping,
    int? funnelStage,
    int? speedScore,
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
      ping: ping ?? this.ping,
      funnelStage: funnelStage ?? this.funnelStage,
      speedScore: speedScore ?? this.speedScore,
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
    'ping': ping,
    'funnelStage': funnelStage,
    'speedScore': speedScore,
    'stageResults': stageResults.map((k, v) => MapEntry<String, dynamic>(k, v.toJson())),
    'lastFailedStage': lastFailedStage,
    'failureReason': failureReason,
    'lastTestedAt': lastTestedAt?.toIso8601String(),
  };

  factory VpnConfigWithMetrics.fromJson(Map<String, dynamic> json) {
    return VpnConfigWithMetrics(
      id: json['id']?.toString() ?? '',
      rawConfig: json['rawConfig']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      countryCode: json['countryCode'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      // Default to Epoch 0 for migration safety (existing configs won't have this field)
      addedDate: json['addedDate'] != null
          ? DateTime.parse(json['addedDate'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
      deviceMetrics: (json['deviceMetrics'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry<String, DeviceMetrics>(k, DeviceMetrics.fromJson(v as Map<String, dynamic>)),
      ) ?? {},
      failureCount: json['failureCount'] as int? ?? 0,
      lastSuccessfulConnectionTime: json['lastSuccessfulConnectionTime'] as int? ?? 0,
      isAlive: json['isAlive'] as bool? ?? true,
      tier: json['tier'] as int? ?? 0,
      ping: json['ping'] as int? ?? -1,
      // Default to 0 for missing keys (Migration Safety)
      funnelStage: json['funnelStage'] as int? ?? 0,
      speedScore: json['speedScore'] as int? ?? 0,
      stageResults: (json['stageResults'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry<String, TestResult>(k, TestResult.fromJson(v as Map<String, dynamic>)),
      ) ?? {},
      lastFailedStage: json['lastFailedStage'] as String?,
      failureReason: json['failureReason'] as String?,
      lastTestedAt: json['lastTestedAt'] != null ? DateTime.parse(json['lastTestedAt'] as String) : null,
    );
  }

  @override
  int compareTo(VpnConfigWithMetrics other) {
    // 1. Alive/Verified (Funnel > 0 OR Ping > 0)
    bool amAlive = this.funnelStage > 0 || this.currentPing > 0;
    bool otherAlive = other.funnelStage > 0 || other.currentPing > 0;

    if (amAlive != otherAlive) {
        return amAlive ? -1 : 1; // Alive comes first
    }

    // If both Alive: Sort by Funnel/Speed/Ping
    if (amAlive) {
        if (this.funnelStage != other.funnelStage) {
            return other.funnelStage.compareTo(this.funnelStage); // Descending
        }
        if (this.speedScore != other.speedScore) {
            return other.speedScore.compareTo(this.speedScore); // Descending
        }
        int myPing = (this.currentPing <= 0) ? 999999 : this.currentPing;
        int otherPing = (other.currentPing <= 0) ? 999999 : other.currentPing;
        return myPing.compareTo(otherPing); // Ascending (Lower is better)
    }

    // If both Dead/Unknown (Not Alive):
    // 2. PURGATORY CHECK: Last Success Time (Desc)
    if (this.lastSuccessfulConnectionTime != other.lastSuccessfulConnectionTime) {
        return other.lastSuccessfulConnectionTime.compareTo(this.lastSuccessfulConnectionTime);
    }

    // 3. Fallback: Added Date (Newer first)
    return other.addedDate.compareTo(this.addedDate);
  }
}
