import 'dart:convert';
import 'dart:io';

void main() async {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('Error: pubspec.yaml not found');
    exit(1);
  }

  // Read version and build code from assets/version.json if available
  final versionJsonFile = File('assets/version.json');
  String version = '1.0.4';
  int versionCode = 1004;

  if (versionJsonFile.existsSync()) {
    try {
      final json = jsonDecode(await versionJsonFile.readAsString());
      if (json['version'] != null) {
        version = json['version'].toString().trim();
      }
      if (json['version_code'] != null) {
        versionCode = int.tryParse(json['version_code'].toString()) ?? versionCode;
      }
      print('Loaded version config from assets/version.json: $version+$versionCode');
    } catch (e) {
      print('Warning: Failed to parse assets/version.json: $e');
    }
  }

  final newVersion = '$version+$versionCode';

  final lines = await pubspecFile.readAsLines();
  final newLines = <String>[];
  bool updated = false;

  for (var line in lines) {
    if (line.trim().startsWith('version:')) {
      print('Updating pubspec.yaml version to: $newVersion');
      newLines.add('version: $newVersion');
      updated = true;
    } else {
      newLines.add(line);
    }
  }

  if (updated) {
    await pubspecFile.writeAsString('${newLines.join('\n')}\n');
    print('✅ pubspec.yaml version updated successfully to $newVersion');
  } else {
    print('⚠️ Error: Could not find "version:" line in pubspec.yaml');
    exit(1);
  }
}
