import '../utils/connectivity_utils.dart';

class ConnectivityService {
  final Future<bool> Function() _internetChecker;

  ConnectivityService({Future<bool> Function()? internetChecker})
    : _internetChecker = internetChecker ?? ConnectivityUtils.hasInternet;

  Future<bool> hasInternet() async {
    return _internetChecker();
  }
}
