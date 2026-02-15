// ignore_for_file: avoid_print

import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;

const String kSingBoxVersion = 'v1.10.1';
// GitHub Release URL pattern:
// https://github.com/SagerNet/sing-box/releases/download/v1.10.1/sing-box-1.10.1-android-arm64.tar.gz
const String kBaseUrl = 'https://github.com/SagerNet/sing-box/releases/download/$kSingBoxVersion';

final String kAndroidUrl = '$kBaseUrl/sing-box-${kSingBoxVersion.substring(1)}-android-arm64.tar.gz';
final String kWindowsUrl = '$kBaseUrl/sing-box-${kSingBoxVersion.substring(1)}-windows-amd64.zip';

// GeoIP/GeoSite URLs (using latest releases)
const String kGeoIpUrl = 'https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db';
const String kGeoSiteUrl = 'https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db';

final Directory kAssetsDir = Directory('assets/executables');
final Directory kAndroidDir = Directory('${kAssetsDir.path}/android');
final Directory kWindowsDir = Directory('${kAssetsDir.path}/windows');

void main() async {
  print('🚀 Starting Sing-box setup for version $kSingBoxVersion...');

  try {
    // 1. Clean directories
    await _cleanDirectories();

    // 2. Download and process Android
    await _processAndroid();

    // 3. Download and process Windows
    await _processWindows();

    // 4. Download GeoIP/GeoSite (Windows only as Android usually downloads internally or we bundle same DBs)
    // The requirement says "extract geoip.db and geosite.db and place them in assets/executables/windows/"
    await _downloadGeoAssets();

    print('✅ Setup complete! Assets are ready in assets/executables/');
  } catch (e) {
    print('❌ Setup failed: $e');
    exit(1);
  }
}

Future<void> _cleanDirectories() async {
  print('🧹 Cleaning existing assets...');

  if (await kAndroidDir.exists()) {
    await for (final entity in kAndroidDir.list()) {
      if (entity is File && entity.path.endsWith('.gitkeep')) continue;
      await entity.delete(recursive: true);
    }
  } else {
    await kAndroidDir.create(recursive: true);
  }

  if (await kWindowsDir.exists()) {
    await for (final entity in kWindowsDir.list()) {
       if (entity is File && entity.path.endsWith('.gitkeep')) continue;
      await entity.delete(recursive: true);
    }
  } else {
    await kWindowsDir.create(recursive: true);
  }
}

Future<void> _processAndroid() async {
  print('⬇️ Downloading Android binary from $kAndroidUrl...');
  final archiveBytes = await _downloadFile(kAndroidUrl);

  print('📦 Extracting Android binary...');
  final tarBytes = GZipDecoder().decodeBytes(archiveBytes);
  final archive = TarDecoder().decodeBytes(tarBytes);

  bool found = false;
  for (final file in archive) {
    if (file.name.endsWith('sing-box') && !file.name.endsWith('.tar.gz') && !file.name.endsWith('.zip')) {
      final filename = 'libsingbox.so';
      final path = '${kAndroidDir.path}/$filename';
      print('   -> Extracting ${file.name} to $path');

      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(file.content as List<int>);

      found = true;
      break;
    }
  }

  if (!found) {
    throw Exception('sing-box binary not found in Android archive.');
  }
}

Future<void> _processWindows() async {
  print('⬇️ Downloading Windows binary from $kWindowsUrl...');
  final archiveBytes = await _downloadFile(kWindowsUrl);

  print('📦 Extracting Windows binary...');
  final archive = ZipDecoder().decodeBytes(archiveBytes);

  bool found = false;
  for (final file in archive) {
    if (file.isFile && file.name.endsWith('sing-box.exe')) {
      final path = '${kWindowsDir.path}/sing-box.exe';
      print('   -> Extracting ${file.name} to $path');
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(file.content as List<int>);
      found = true;
      break;
    }
  }

  if (!found) {
    throw Exception('sing-box.exe not found in Windows archive.');
  }
}

Future<void> _downloadGeoAssets() async {
  print('⬇️ Downloading GeoIP database...');
  final geoipBytes = await _downloadFile(kGeoIpUrl);
  final geoipPath = '${kWindowsDir.path}/geoip.db';
  File(geoipPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(geoipBytes);
  print('   -> Saved to $geoipPath');

  print('⬇️ Downloading GeoSite database...');
  final geositeBytes = await _downloadFile(kGeoSiteUrl);
  final geositePath = '${kWindowsDir.path}/geosite.db';
  File(geositePath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(geositeBytes);
  print('   -> Saved to $geositePath');
}


Future<List<int>> _downloadFile(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    return response.bodyBytes;
  } else if (response.statusCode == 302 || response.statusCode == 301) {
    final newUrl = response.headers['location'];
    if (newUrl != null) return _downloadFile(newUrl);
    throw Exception('Redirect with no location: $url');
  } else {
    throw Exception('Failed to download $url: ${response.statusCode} ${response.reasonPhrase}');
  }
}
