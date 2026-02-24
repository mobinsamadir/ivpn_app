import 'dart:io';

void main() async {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('Error: pubspec.yaml not found');
    exit(1);
  }

  final lines = await pubspecFile.readAsLines();
  final newLines = <String>[];
  bool updated = false;

  // Generate timestamp-based build number (Unix timestamp)
  // This ensures every build is "newer" than the last one.
  final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // We keep the semantic version 1.0.0 but update the build number
  // Format: 1.0.0+<timestamp>
  final newVersion = '1.0.0+$timestamp';

  for (var line in lines) {
    if (line.trim().startsWith('version:')) {
      print('Updating version to: $newVersion');
      newLines.add('version: $newVersion');
      updated = true;
    } else {
      newLines.add(line);
    }
  }

  if (updated) {
    await pubspecFile.writeAsString(newLines.join('\n') + '\n');
    print('✅ pubspec.yaml version updated successfully to $newVersion');
  } else {
    print('⚠️ Error: Could not find "version:" line in pubspec.yaml');
    exit(1);
  }
}
