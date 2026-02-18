import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

const singboxVersion = 'v1.10.1';
const windowsUrl =
    'https://github.com/SagerNet/sing-box/releases/download/$singboxVersion/sing-box-1.10.1-windows-amd64.zip';
const geoipUrl =
    'https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db';
const geositeUrl =
    'https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db';

// Thresholds
const int minExeSize = 5 * 1024 * 1024; // 5MB
const int minDbSize = 2 * 1024 * 1024;  // 2MB

void main() async {
  print('Starting robust setup_core...');

  final windowsDir = Directory('assets/executables/windows');
  final assetsDir = Directory('assets');

  try {
    if (!await windowsDir.exists()) {
      await windowsDir.create(recursive: true);
    }
    if (!await assetsDir.exists()) {
      await assetsDir.create(recursive: true);
    }
  } catch (e) {
    print('Critical Error: Failed to create directories: $e');
    exit(1);
  }

  // --- 1. WINDOWS BINARY (Crucial) ---
  final windowsBinary = File(p.join(windowsDir.path, 'sing-box.exe'));
  bool validExe = await _validateFile(windowsBinary, minExeSize, 'Windows Sing-box');

  if (validExe) {
    // Perform Execution Check (The "Gold Standard")
    validExe = await _checkBinaryExecution(windowsBinary);
  }

  if (!validExe) {
    if (await windowsBinary.exists()) {
       print('Corrupt/Invalid binary detected. Deleting to force re-download...');
       try { await windowsBinary.delete(); } catch(e) { print('Error deleting binary: $e'); }
    }

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
        await File(windowsBinary.path).writeAsBytes(singboxFile.content as List<int>);
        print('Saved to ${windowsBinary.path}');

        // Final Validation
        if (!await _checkBinaryExecution(windowsBinary)) {
           throw Exception("Newly downloaded binary failed execution check.");
        }
      } else {
        print('Critical Error: sing-box.exe not found in Windows archive.');
        exit(1);
      }
    } catch (e) {
      print('Critical Error setting up Windows Sing-box: $e');
      exit(1);
    }
  } else {
    print('Windows Sing-box is valid and healthy.');
  }

  // --- 2. GEOIP ---
  final geoipFile = File(p.join(assetsDir.path, 'geoip.db'));
  bool validGeoip = await _validateFile(geoipFile, minDbSize, 'GeoIP');

  if (!validGeoip) {
    if (await geoipFile.exists()) await geoipFile.delete();
    print('Downloading GeoIP ($geoipUrl)...');
    try {
      final bytes = await downloadFile(geoipUrl);
      await geoipFile.writeAsBytes(bytes);
      print('Saved to ${geoipFile.path}');
      if (!await _validateFile(geoipFile, minDbSize, 'GeoIP (Post-Download)')) {
         throw Exception("Downloaded GeoIP is too small/corrupt.");
      }
    } catch (e) {
      print('Critical Error downloading GeoIP: $e');
      exit(1);
    }
  } else {
    print('GeoIP is valid.');
  }

  // --- 3. GEOSITE ---
  final geositeFile = File(p.join(assetsDir.path, 'geosite.db'));
  bool validGeosite = await _validateFile(geositeFile, minDbSize, 'Geosite');

  if (!validGeosite) {
    if (await geositeFile.exists()) await geositeFile.delete();
    print('Downloading Geosite ($geositeUrl)...');
    try {
      final bytes = await downloadFile(geositeUrl);
      await geositeFile.writeAsBytes(bytes);
      print('Saved to ${geositeFile.path}');
      if (!await _validateFile(geositeFile, minDbSize, 'Geosite (Post-Download)')) {
         throw Exception("Downloaded Geosite is too small/corrupt.");
      }
    } catch (e) {
      print('Critical Error downloading Geosite: $e');
      exit(1);
    }
  } else {
    print('Geosite is valid.');
  }

  // --- 4. COPY ASSETS TO WINDOWS DIR ---
  try {
     await geoipFile.copy(p.join(windowsDir.path, 'geoip.db'));
     await geositeFile.copy(p.join(windowsDir.path, 'geosite.db'));
     print('Copied geo assets to windows executable folder.');
  } catch (e) {
     print('Warning: Could not copy geo assets to windows folder: $e');
  }

  print('Setup complete.');
}

Future<bool> _validateFile(File file, int minSize, String label) async {
  if (!await file.exists()) return false;
  final size = await file.length();
  if (size < minSize) {
    print('[Validation Fail] $label is too small (${(size / 1024 / 1024).toStringAsFixed(2)}MB < ${(minSize / 1024 / 1024).toStringAsFixed(2)}MB). Treating as corrupt.');
    return false;
  }
  return true;
}

Future<bool> _checkBinaryExecution(File binary) async {
  if (!Platform.isWindows) {
      print('[Skip] Execution check skipped (Not on Windows).');
      return true; // Assume valid on non-Windows build envs
  }

  print('Running execution check on ${binary.path}...');
  try {
    final result = await Process.run(
      binary.path,
      ['version'],
      runInShell: true,
    ).timeout(const Duration(seconds: 5), onTimeout: () {
       throw TimeoutException("Execution timed out");
    });

    if (result.exitCode == 0) {
       print('Execution check passed: ${result.stdout.toString().trim()}');
       return true;
    } else {
       print('Execution check failed (Exit Code ${result.exitCode}): ${result.stderr}');
       return false;
    }
  } catch (e) {
    print('Execution check failed/crashed: $e');
    if (e is TimeoutException) {
       print('FATAL: Binary hung during version check. Treating as corrupt.');
    }
    return false;
  }
}

Future<List<int>> downloadFile(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    return response.bodyBytes;
  } else {
    throw Exception('Failed to download file: ${response.statusCode}');
  }
}
