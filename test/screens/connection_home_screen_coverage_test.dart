import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/screens/connection_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ConnectionHomeScreen Widget functions coverage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'wallet_balance': 100});
    });

    testWidgets('buildConnectButtonForTest - isConnected true coverage',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildConnectButtonForTest(
              isConnected: true,
              isConnecting: false,
              onRefresh: () {},
              onConnect: () {},
              onSkip: () {},
            ),
          ),
        ),
      );
      expect(find.byType(GestureDetector), findsWidgets);
    });
    testWidgets('buildConnectButtonForTest - isConnecting true coverage',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildConnectButtonForTest(
              isConnected: false,
              isConnecting: true,
              onRefresh: () {},
              onConnect: () {},
              onSkip: () {},
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
    testWidgets('buildConnectionStatusForTest - fail state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildConnectionStatusForTest(
              isConnected: false,
              connectionStatus: 'Error occurred',
              rxBytes: 100,
              txBytes: 200,
            ),
          ),
        ),
      );
      expect(find.text('Error occurred'), findsWidgets);
    });
    testWidgets('buildConnectionStatusForTest - disconnected state',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildConnectionStatusForTest(
              isConnected: false,
              connectionStatus: 'DISCONNECTED',
              rxBytes: 100,
              txBytes: 200,
            ),
          ),
        ),
      );
      expect(find.text('DISCONNECTED'), findsWidgets);
    });
  });
}
