class ServerTestResult {
  final String serverId;
  final HealthMetrics health;
  final SpeedMetrics? speed;
  final StabilityMetrics? stability;
  final double finalScore;
  final DateTime testTime;

  ServerTestResult({
    required this.serverId,
    required this.health,
    this.speed,
    this.stability,
    required this.finalScore,
    required this.testTime,
  });

  factory ServerTestResult.initial(String serverId) {
    return ServerTestResult(
      serverId: serverId,
      health: HealthMetrics.empty(),
      finalScore: 0,
      testTime: DateTime.now(),
    );
  }

  ServerTestResult copyWith({
    HealthMetrics? health,
    SpeedMetrics? speed,
    StabilityMetrics? stability,
    double? finalScore,
  }) {
    return ServerTestResult(
      serverId: serverId,
      health: health ?? this.health,
      speed: speed ?? this.speed,
      stability: stability ?? this.stability,
      finalScore: finalScore ?? this.finalScore,
      testTime: testTime,
    );
  }
}

class HealthMetrics {
  final Map<String, int> endpointLatencies; // endpoint -> latency
  final double successRate;
  final int averageLatency;
  final bool dnsWorking;

  HealthMetrics({
    required this.endpointLatencies,
    required this.successRate,
    required this.averageLatency,
    required this.dnsWorking,
  });

  factory HealthMetrics.empty() {
    return HealthMetrics(
      endpointLatencies: {},
      successRate: 0,
      averageLatency: -1,
      dnsWorking: false,
    );
  }
}

class SpeedMetrics {
  final double downloadMbps;
  final double uploadMbps;
  final String testFileUsed;
  final Duration downloadDuration;

  SpeedMetrics({
    required this.downloadMbps,
    this.uploadMbps = 0,
    required this.testFileUsed,
    required this.downloadDuration,
  });
}

class StabilityMetrics {
  final List<int> samples;
  final int failureCount;
  final double jitter;
  final double packetLoss;
  final double averageLatency;
  final int maxLatency;
  final int minLatency;
  final double standardDeviation;
  final DateTime startTime;
  final DateTime endTime;

  StabilityMetrics({
    required this.samples,
    required this.failureCount,
    required this.jitter,
    required this.packetLoss,
    required this.averageLatency,
    required this.maxLatency,
    required this.minLatency,
    required this.standardDeviation,
    required this.startTime,
    required this.endTime,
  });

  factory StabilityMetrics.empty() {
    return StabilityMetrics(
      samples: [],
      failureCount: 0,
      jitter: 0,
      packetLoss: 0,
      averageLatency: 0,
      maxLatency: 0,
      minLatency: 0,
      standardDeviation: 0,
      startTime: DateTime.now(),
      endTime: DateTime.now(),
    );
  }
}
