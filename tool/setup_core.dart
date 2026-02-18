import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

const singboxVersion = 'v1.10.1';
// Android binary download removed as we use JNI (libbox.aar) now.
const windowsUrl =
    'https://github.com/SagerNet/sing-box/releases/download/$singboxVersion/sing-box-1.10.1-windows-amd64.zip';
const geoipUrl =
    'https://github.com/v2fly/geoip/releases/latest/download/geoip.dat';
const geositeUrl =
    'https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat';

void main() async {
  print('Starting setup_core...');

  final windowsDir = Directory('assets/executables/windows');

  try {
    if (!await windowsDir.exists()) {
      await windowsDir.create(recursive: true);
    }
  } catch (e) {
    print('Critical Error: Failed to create directories: $e');
    exit(1);
  }

  // 1. Android Sing-box (REMOVED)
  // Logic removed to save APK size (~15MB). Android uses libbox.aar via JNI.

  // 2. Windows Sing-box
  final windowsBinary = File(p.join(windowsDir.path, 'sing-box.exe'));
  if (!await windowsBinary.exists()) {
    print('Downloading Windows Sing-box ($windowsUrl)...');
    try {
      final bytes = await downloadFile(windowsUrl);
      print('Extracting Windows Sing-box...');
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? singboxFile;
      for (final file in archive) {
        if (file.name.endsWith('sing-box.exe')) {
          singboxFile = file;
          break;
        }
      }

      if (singboxFile != null) {
        await File(
          windowsBinary.path,
        ).writeAsBytes(singboxFile.content as List<int>);
        print('Saved to ${windowsBinary.path}');
      } else {
        print('Critical Error: sing-box.exe not found in Windows archive.');
        exit(1);
      }
    } catch (e) {
      print('Critical Error setting up Windows Sing-box: $e');
      exit(1);
    }
  } else {
    print('Windows Sing-box already exists.');
  }

  // 3. GeoIP
  final geoipFile = File(p.join(windowsDir.path, 'geoip.db'));
  if (!await geoipFile.exists()) {
    print('Downloading GeoIP ($geoipUrl)...');
    try {
      final bytes = await downloadFile(geoipUrl);
      await geoipFile.writeAsBytes(bytes);
      print('Saved to ${geoipFile.path}');
    } catch (e) {
      print('Critical Error downloading GeoIP: $e');
      exit(1);
    }
  } else {
    print('GeoIP already exists.');
  }

  // 4. Geosite
  final geositeFile = File(p.join(windowsDir.path, 'geosite.db'));
  if (!await geositeFile.exists()) {
    print('Downloading Geosite ($geositeUrl)...');
    try {
      final bytes = await downloadFile(geositeUrl);
      await geositeFile.writeAsBytes(bytes);
      print('Saved to ${geositeFile.path}');
    } catch (e) {
      print('Critical Error downloading Geosite: $e');
      exit(1);
    }
  } else {
    print('Geosite already exists.');
  }

  print('Setup complete.');
}

Future<List<int>> downloadFile(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    return response.bodyBytes;
  } else {
    throw Exception('Failed to download file: ${response.statusCode}');
  }
}
