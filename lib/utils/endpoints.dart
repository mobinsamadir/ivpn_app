final List<String> adaptiveSpeedTestEndpoints = [
  // Use HTTPS directly (bypass proxy for testing)
  'https://httpbin.org/bytes/100000',      // 100KB
  'https://httpbin.org/bytes/500000',      // 500KB
  'https://httpbin.org/bytes/1000000',     // 1MB
  
  // Backup: Public speed test endpoints
  'https://speedtest.tele2.net/1MB.zip',
  'https://ipv4.download.thinkbroadband.com/5MB.zip',
];

class TestEndpoints {
  // New Constants (Extracted)
  static const String connectivityCheck = 'http://connectivitycheck.gstatic.com/generate_204';
  static const String speedCloudflare = 'http://speed.cloudflare.com/__down?bytes=1000000';

  static const List<String> pingEndpoints = [
    'http://www.gstatic.com/generate_204',
    connectivityCheck,
    'http://cp.cloudflare.com',
    'http://api.ipify.org?format=json',
  ];
  
  static List<String> get speedSmall => [adaptiveSpeedTestEndpoints[0]];
  static List<String> get speedMedium => [adaptiveSpeedTestEndpoints[1]];
  static List<String> get speedLarge => [adaptiveSpeedTestEndpoints[2]];
}
