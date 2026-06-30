import sys

with open('lib/services/config_manager.dart', 'r') as f:
    content = f.read()

search = """    try {
      // Initiate native connection
      await nativeService.connect(target.rawConfig);

      // Wait for CONNECTED state with strict 15-second timeout
      await nativeService.connectionStatusStream
          .firstWhere((status) => status == 'CONNECTED')
          .timeout(const Duration(seconds: 15));"""

replace = """    try {
      // Initiate native connection
      await nativeService.connect(target.rawConfig);

      // Wait for CONNECTED state with strict 15-second timeout
      await nativeService.connectionStatusStream
          .firstWhere((status) => status == 'CONNECTED' || status.startsWith('ERROR'))
          .timeout(const Duration(seconds: 15), onTimeout: () {
            throw Exception('Timeout waiting for CONNECTED state');
          }).then((status) {
            if (status.startsWith('ERROR')) {
              throw Exception('Native connection failed: $status');
            }
          });"""

if search in content:
    content = content.replace(search, replace)
    with open('lib/services/config_manager.dart', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
