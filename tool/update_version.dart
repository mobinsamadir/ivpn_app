import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('Error: pubspec.yaml not found');
    exit(1);
  }

  String? cliVersion;
  int? cliCode;

  for (int i = 0; i < args.length; i++) {
    if ((args[i] == '--version' || args[i] == '-v') && i + 1 < args.length) {
      cliVersion = args[i + 1].trim();
      i++;
    } else if ((args[i] == '--code' || args[i] == '-c') && i + 1 < args.length) {
      cliCode = int.tryParse(args[i + 1].trim());
      i++;
    }
  }

  // Read base version and build code from assets/version.json if available
  final versionJsonFile = File('assets/version.json');
  String version = '2.0.0';
  int versionCode = 2000;

  if (versionJsonFile.existsSync()) {
    try {
      final json = jsonDecode(await versionJsonFile.readAsString());
      if (json['version'] != null) {
        version = json['version'].toString().trim();
      }
      if (json['version_code'] != null) {
        versionCode = int.tryParse(json['version_code'].toString()) ?? versionCode;
      }
      print('Loaded base version config from assets/version.json: $version+$versionCode');
    } catch (e) {
      print('Warning: Failed to parse assets/version.json: $e');
    }
  }

  if (cliVersion != null && cliVersion.isNotEmpty) {
    version = cliVersion;
    print('Applied CLI version override: $version');
  }
  if (cliCode != null) {
    versionCode = cliCode;
    print('Applied CLI versionCode override: $versionCode');
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
