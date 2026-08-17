import 'dart:io';

void main() {
  final file = File('lib/services/ad_manager_service.dart');
  var content = file.readAsStringSync();

  if (!content.contains('import \'package:flutter/foundation.dart\';')) {
    content = content.replaceFirst('import \'package:flutter/material.dart\';',
        'import \'package:flutter/material.dart\';\nimport \'package:flutter/foundation.dart\';');
  }

  content = content.replaceAll('final jsonMap = jsonDecode(jsonString);',
      'final jsonMap = await compute(_parseJsonInBackground, jsonString);');

  content = content.replaceAll('data = jsonDecode(data);',
      'data = await compute(_parseJsonInBackground, data);');

  if (!content.contains('_parseJsonInBackground')) {
    content +=
        '\n// Top-level function for background isolate JSON decoding\ndynamic _parseJsonInBackground(String source) => jsonDecode(source);\n';
  }

  file.writeAsStringSync(content);
}
