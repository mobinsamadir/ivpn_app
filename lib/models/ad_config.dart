class AdConfig {
  final String configVersion;
  final Map<String, AdUnit> ads;

  AdConfig({
    required this.configVersion,
    required this.ads,
  });

  factory AdConfig.fromJson(Map<String, dynamic> json) {
    final adsJson = json['ads'] as Map<String, dynamic>? ?? {};
    final adsMap = adsJson.map(
      (key, value) => MapEntry(key, AdUnit.fromJson(value as Map<String, dynamic>)),
    );

    return AdConfig(
      configVersion: json['config_version'] as String? ?? 'v1',
      ads: adsMap,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'config_version': configVersion,
      'ads': ads.map((key, value) => MapEntry(key, value.toJson())),
    };
  }
}

class AdUnit {
  final bool isEnabled;
  final String type; // 'webview', 'image', 'video'
  final String mediaSource; // URL or raw HTML
  final String targetUrl;
  final int timerSeconds;

  const AdUnit({
    this.isEnabled = true,
    this.type = 'webview',
    this.mediaSource = '',
    this.targetUrl = '',
    this.timerSeconds = 0,
  });

  factory AdUnit.fromJson(Map<String, dynamic> json) {
    return AdUnit(
      isEnabled: json['isEnabled'] as bool? ?? true,
      type: json['type'] as String? ?? 'webview',
      mediaSource: json['mediaSource'] as String? ?? '',
      targetUrl: json['targetUrl'] as String? ?? '',
      timerSeconds: json['timerSeconds'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isEnabled': isEnabled,
      'type': type,
      'mediaSource': mediaSource,
      'targetUrl': targetUrl,
      'timerSeconds': timerSeconds,
    };
  }
}
