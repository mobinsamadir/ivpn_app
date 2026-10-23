import 'dart:convert';
import 'dart:typed_data';

class InstalledApp {
  final String name;
  final String packageName;
  final bool isSystemApp;
  final Uint8List? iconBytes;

  const InstalledApp({
    required this.name,
    required this.packageName,
    required this.isSystemApp,
    this.iconBytes,
  });

  factory InstalledApp.fromMap(Map<dynamic, dynamic> map) {
    Uint8List? bytes;
    final iconStr = map['icon'] as String?;
    if (iconStr != null && iconStr.isNotEmpty) {
      try {
        bytes = base64Decode(iconStr);
      } catch (_) {}
    }

    return InstalledApp(
      name: map['name'] as String? ?? 'Unknown App',
      packageName: map['packageName'] as String? ?? '',
      isSystemApp: map['isSystemApp'] as bool? ?? false,
      iconBytes: bytes,
    );
  }

  /// Checks if this app is a known Iranian banking, ride-hailing, or local service app
  bool get isIranianApp {
    final lowerPkg = packageName.toLowerCase();
    final lowerName = name.toLowerCase();

    // Known package keywords and Iranian service identifiers
    const iranianKeywords = [
      'snapp',
      'tapsi',
      'tap30',
      'divar',
      'torob',
      'bale',
      'rubika',
      'eitaa',
      'soroush',
      'gap.im',
      'neshan',
      'balad',
      'digikala',
      'alibaba',
      'mci',
      'irancell',
      'rightel',
      'tejarat',
      'mellat',
      'melli',
      'saderat',
      'sepah',
      'resalat',
      'blubank',
      'ap',
      'asanpardakht',
      'parsian',
      'pasargad',
      'saman',
      'keshavarzi',
      'maskan',
      'refah',
      'shahr',
      'sina',
      'karafarin',
      'postbank',
      'nobitex',
      'wallex',
      'tabdeal',
      'abantether',
      'bank',
      'hamrah',
    ];

    if (lowerPkg.endsWith('.ir') ||
        lowerPkg.contains('.ir.') ||
        lowerPkg.startsWith('ir.')) {
      return true;
    }

    for (final kw in iranianKeywords) {
      if (lowerPkg.contains(kw) || lowerName.contains(kw)) {
        return true;
      }
    }
    return false;
  }
}
