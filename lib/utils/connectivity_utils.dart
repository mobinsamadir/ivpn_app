import 'dart:io';

class ConnectivityUtils {
  static Future<bool> hasInternet({
    Future<List<InternetAddress>> Function(String) lookup =
        InternetAddress.lookup,
  }) async {
    try {
      final result = await lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
