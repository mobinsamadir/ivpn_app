import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

const singboxVersion = 'v1.10.1';
const androidUrl =
    'https://github.com/SagerNet/sing-box/releases/download/$singboxVersion/sing-box-1.10.1-android-arm64.tar.gz';
const windowsUrl =
    'https://github.com/SagerNet/sing-box/releases/download/$singboxVersion/sing-box-1.10.1-windows-amd64.zip';
const geoipUrl =
    'https://github.com/v2fly/geoip/releases/latest/download/geoip.dat';
const geositeUrl =
    'https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat';

void main() async {
  print('Starting setup_core...');

  final androidDir = Directory('assets/executables/android');
  final windowsDir = Directory('assets/executables/windows');

  if (!await androidDir.exists()) {
    await androidDir.create(recursive: true);
  }
  if (!await windowsDir.exists()) {
    await windowsDir.create(recursive: true);
  }

  // 1. Android Sing-box
  final androidBinary = File(p.join(androidDir.path, 'libsingbox.so'));
  if (!await androidBinary.exists()) {
    print('Downloading Android Sing-box ($androidUrl)...');
    try {
      final bytes = await downloadFile(androidUrl);
      print('Extracting Android Sing-box...');
      final archive = TarDecoder().decodeBytes(
        GZipDecoder().decodeBytes(bytes),
      );

      // Find 'sing-box' executable in the archive
      ArchiveFile? singboxFile;
      for (final file in archive) {
        if (file.name.endsWith('sing-box')) {
          singboxFile = file;
          break;
        }
      }

      if (singboxFile != null) {
        await File(
          androidBinary.path,
        ).writeAsBytes(singboxFile.content as List<int>);
        print('Saved to ${androidBinary.path}');

        if (Platform.isLinux || Platform.isMacOS) {
          try {
            await Process.run('chmod', ['+x', androidBinary.path]);
            print('Set executable permissions for Android binary.');
          } catch (e) {
            print('Warning: chmod failed: $e');
          }
        }
      } else {
        print('Error: sing-box binary not found in Android archive.');
      }
    } catch (e) {
      print('Error setting up Android Sing-box: $e');
    }
  } else {
    print('Android Sing-box already exists.');
  }

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
        print('Error: sing-box.exe not found in Windows archive.');
      }
    } catch (e) {
      print('Error setting up Windows Sing-box: $e');
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
      print('Error downloading GeoIP: $e');
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
      print('Error downloading Geosite: $e');
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
