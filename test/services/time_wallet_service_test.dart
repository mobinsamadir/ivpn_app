import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ivpn_new/services/time_wallet_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Time Wallet grants 1 hour of time on reward', () async {
    final wallet = TimeWalletService();
    await wallet.init();

    expect(wallet.remainingSeconds, equals(0));
    expect(wallet.hasTime, isFalse);

    await wallet.rewardTime();

    expect(wallet.remainingSeconds, greaterThanOrEqualTo(3599));
    expect(wallet.remainingSeconds, lessThanOrEqualTo(3600));
    expect(wallet.hasTime, isTrue);
  });
}
