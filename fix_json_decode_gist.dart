import 'dart:io';

void main() {
  final file = File('lib/services/config_gist_service.dart');
  var content = file.readAsStringSync();

  content = content.replaceAll(
    'final data = jsonDecode(response.body);',
    'final data = await compute(_parseJsonInBackground, response.body);'
  );

  content = content.replaceAll(
    'final List<dynamic> rawList = jsonDecode(backupJson);',
    'final List<dynamic> rawList = await compute(_parseJsonInBackground, backupJson);'
  );

  if (!content.contains('_parseJsonInBackground')) {
    content += '\n// Top-level function for background isolate JSON decoding\ndynamic _parseJsonInBackground(String source) => jsonDecode(source);\n';
  }

  file.writeAsStringSync(content);
}
