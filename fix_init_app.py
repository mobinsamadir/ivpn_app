import sys

with open('lib/screens/connection_home_screen.dart', 'r') as f:
    content = f.read()

search = """  Future<void> _initialize() async {
    try {
      await _loadPreferences();
      if (!_isInitialized) {
        setState(() {
          _isInitialized = true;
        });
      }
      AdvancedLogger.info('[HomeScreen] Initialized successfully');

      // Start app sequence now that preferences are loaded
      _initAppSequence();
    } catch (e) {
      AdvancedLogger.error('[HomeScreen] Initialization failed: $e');
    }
  }"""

replace = """  Future<void> _initialize() async {
    try {
      await _loadPreferences();
      if (!_isInitialized) {
        setState(() {
          _isInitialized = true;
        });
      }
      AdvancedLogger.info('[HomeScreen] Initialized successfully');

      // Start app sequence now that preferences are loaded
      await _initAppSequence();
    } catch (e) {
      AdvancedLogger.error('[HomeScreen] Initialization failed: $e');
    }
  }"""

if search in content:
    content = content.replace(search, replace)
    with open('lib/screens/connection_home_screen.dart', 'w') as f:
        f.write(content)
    print("Successfully replaced.")
else:
    print("Search string not found.")
