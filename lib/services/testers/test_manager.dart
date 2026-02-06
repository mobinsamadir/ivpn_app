import '../../utils/advanced_logger.dart';

class CancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class TestManager {
  static final Map<int, CancellationToken> _activeTests = {};

  static bool isServerBusy(int index) {
    return _activeTests.containsKey(index);
  }

  static CancellationToken startTest(int index) {
    AdvancedLogger.debug("TestManager: Starting test for server #$index");
    // If there's an existing test, cancel it first
    if (_activeTests.containsKey(index)) {
      AdvancedLogger.debug("TestManager: Cancelling existing test for #$index before restart");
      _activeTests[index]?.cancel();
    }
    
    final token = CancellationToken();
    _activeTests[index] = token;
    return token;
  }

  static void stopTest(int index) {
    AdvancedLogger.debug("TestManager: Manual stop requested for server #$index");
    _activeTests[index]?.cancel();
    _activeTests.remove(index);
  }

  static void cleanUp(int index) {
    AdvancedLogger.debug("TestManager: Cleaning up state for server #$index");
    _activeTests.remove(index);
  }
  
  static void resetAll() {
    AdvancedLogger.debug("TestManager: RESET ALL called. Clearing all active tests.");
    for (var token in _activeTests.values) {
      token.cancel();
    }
    _activeTests.clear();
  }
  
  static bool checkCancelled(int index) {
    return _activeTests[index]?.isCancelled ?? false;
  }
}
