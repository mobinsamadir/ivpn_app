import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/screens/connection_home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionHomeScreen Full Initialization', () {
    testWidgets('Renders Scaffold and can be pumped', (WidgetTester tester) async {
       await tester.pumpWidget(
         MaterialApp(
           home: ConnectionHomeScreen(),
         ),
       );
       await tester.pump();
       expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('_ConnectButton Widget Tests', () {
    testWidgets('displays CONNECT text when disconnected', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildConnectButtonForTest(
              isConnected: false,
              isConnecting: false,
              onRefresh: () {},
              onConnect: () {},
              onSkip: () {},
            ),
          ),
        ),
      );

      expect(find.text('CONNECT'), findsOneWidget);
      expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'displays CONNECTING text and CircularProgressIndicator when connecting',
      (WidgetTester tester) async {
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

        expect(find.text('CONNECTING'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.power_settings_new), findsNothing);
      },
    );

    testWidgets('displays CONNECTED text when connected', (
      WidgetTester tester,
    ) async {
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

      expect(find.text('CONNECTED'), findsOneWidget);
      expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('fires callbacks correctly', (WidgetTester tester) async {
      bool refreshTapped = false;
      bool connectTapped = false;
      bool skipTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildConnectButtonForTest(
              isConnected: false,
              isConnecting: false,
              onRefresh: () => refreshTapped = true,
              onConnect: () => connectTapped = true,
              onSkip: () => skipTapped = true,
            ),
          ),
        ),
      );

      // Tap Refresh
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      // Tap Connect (the main animated container doesn't have an icon, we can tap the text)
      await tester.tap(find.text('CONNECT'));
      // Tap Skip
      await tester.tap(find.byIcon(Icons.skip_next_rounded));

      await tester.pump();

      expect(refreshTapped, isTrue);
      expect(connectTapped, isTrue);
      expect(skipTapped, isTrue);
    });
  });

  group('_ConnectionStatus Widget Tests', () {
    testWidgets('displays CONNECTED text with correct color and RX/TX bytes', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildConnectionStatusForTest(
              isConnected: true,
              connectionStatus: 'CONNECTED',
              rxBytes: 2048,
              txBytes: 1048576,
            ),
          ),
        ),
      );

      final statusTextFinder = find.text('CONNECTED');
      expect(statusTextFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(statusTextFinder.first);
      expect(textWidget.style?.color, Colors.greenAccent);

      // 2048 bytes = 2.0 KB
      expect(find.text('2.0 KB'), findsOneWidget);
      // 1048576 bytes = 1.0 MB
      expect(find.text('1.0 MB'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets(
      'displays error text in red and hides RX/TX bytes when failed',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: buildConnectionStatusForTest(
                isConnected: false,
                connectionStatus: 'Failed',
                rxBytes: 0,
                txBytes: 0,
              ),
            ),
          ),
        );

        final statusTextFinder = find.text('Failed');
        expect(statusTextFinder, findsOneWidget);

        final textWidget = tester.widget<Text>(statusTextFinder.first);
        expect(textWidget.style?.color, Colors.redAccent);

        expect(find.byIcon(Icons.arrow_downward), findsNothing);
        expect(find.byIcon(Icons.arrow_upward), findsNothing);
      },
    );

    testWidgets(
      'displays neutral text in grey and hides RX/TX bytes when disconnected',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: buildConnectionStatusForTest(
                isConnected: false,
                connectionStatus: 'DISCONNECTED',
                rxBytes: 0,
                txBytes: 0,
              ),
            ),
          ),
        );

        final statusTextFinder = find.text('DISCONNECTED');
        expect(statusTextFinder, findsOneWidget);

        final textWidget = tester.widget<Text>(statusTextFinder.first);
        expect(textWidget.style?.color, Colors.grey);

        expect(find.byIcon(Icons.arrow_downward), findsNothing);
        expect(find.byIcon(Icons.arrow_upward), findsNothing);
      },
    );
  });
}
