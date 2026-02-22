import '../utils/connectivity_utils.dart';

class ConnectivityService {
  Future<bool> hasInternet() async {
    return ConnectivityUtils.hasInternet();
  }
}
