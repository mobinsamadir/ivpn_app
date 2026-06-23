import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/config_card.dart';
import 'package:ivpn_new/models/vpn_config_with_metrics.dart';

void main() {
  testWidgets('ConfigCard renders config data correctly', (WidgetTester tester) async {
    final mockConfig = VpnConfigWithMetrics(
      id: 'test-1',
      rawConfig: 'vless://test@127.0.0.1:443?security=tls#TestProxy',
      name: 'TestProxy',
      addedDate: DateTime.now(),
      ping: 120, // using correct property name
    );

    bool connectCalled = false;
    bool speedTestCalled = false;
    bool toggleFavoriteCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfigCard(
            config: mockConfig,
            isSelected: false,
            isTesting: false,
            onTap: () => connectCalled = true,
            onTestLatency: () {},
            onTestSpeed: () => speedTestCalled = true,
            onToggleFavorite: () => toggleFavoriteCalled = true,
            onDelete: () {},
          ),
        ),
      ),
    );

    // Verify Title
    expect(find.text('TestProxy'), findsOneWidget);
    
    // Verify Ping shows up
    expect(find.text('120ms'), findsOneWidget);

    // Verify Interactions
    await tester.tap(find.byType(InkWell).first);
    expect(connectCalled, isTrue);

  });
}
