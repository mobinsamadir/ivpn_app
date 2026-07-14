import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/widgets/sliver_tab_bar_delegate.dart';

void main() {
  group('SliverTabBarDelegate', () {
    testWidgets('renders TabBar with correct background color',
        (WidgetTester tester) async {
      const tabBar = TabBar(
        tabs: [
          Tab(text: 'Tab 1'),
          Tab(text: 'Tab 2'),
        ],
      );
      const backgroundColor = Colors.red;

      final delegate = SliverTabBarDelegate(
        tabBar,
        backgroundColor: backgroundColor,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefaultTabController(
              length: 2,
              child: CustomScrollView(
                slivers: [
                  SliverPersistentHeader(
                    delegate: delegate,
                    pinned: true,
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 1000)),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('Tab 1'), findsOneWidget);
      expect(find.text('Tab 2'), findsOneWidget);

      final container = tester.widget<Container>(
        find
            .ancestor(of: find.byType(TabBar), matching: find.byType(Container))
            .first,
      );
      expect(container.color, backgroundColor);
    });

    test('properties return correct values', () {
      const tabBar = TabBar(
        tabs: [
          Tab(text: 'Tab 1'),
        ],
      );
      final delegate =
          SliverTabBarDelegate(tabBar, backgroundColor: Colors.red);

      expect(delegate.minExtent, tabBar.preferredSize.height);
      expect(delegate.maxExtent, tabBar.preferredSize.height);
      expect(delegate.shouldRebuild(delegate), isFalse);
    });
  });
}
