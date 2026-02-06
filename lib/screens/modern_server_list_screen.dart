// lib/screens/modern_server_list_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/server_model.dart';
import '../providers/home_provider.dart';
import '../widgets/server_list_item.dart';

class ModernServerListScreen extends StatefulWidget {
  const ModernServerListScreen({super.key});

  @override
  State<ModernServerListScreen> createState() => _ModernServerListScreenState();
}

class _ModernServerListScreenState extends State<ModernServerListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final List<Tab> _tabs = const [
    Tab(text: 'iVPN'),
    Tab(text: 'Custom'),
    Tab(text: 'Favorites'),
    Tab(text: 'The Best'),
    Tab(text: 'Obsolete'),
  ];

  @override
  void initState() {
    super.initState();
    debugPrint("✅ [ModernServerListScreen] initState called.");
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    debugPrint("🔴 [ModernServerListScreen] dispose called.");
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("🎨 [ModernServerListScreen] Building UI...");

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: _tabs,
                isScrollable: true,
              ),
              Expanded(
                child: Consumer<HomeProvider>(
                  builder: (context, homeProvider, child) {
                    debugPrint(
                      "🔄 [ModernServerListScreen] Consumer rebuilding...",
                    );
                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildServerList(
                          homeProvider,
                          homeProvider.ivpnConfigs,
                          "iVPN",
                        ),
                        _buildServerList(
                          homeProvider,
                          homeProvider.customConfigs,
                          "Custom",
                        ),
                        _buildServerList(
                          homeProvider,
                          homeProvider.favoriteServers,
                          "Favorites",
                        ),
                        _buildServerList(
                          homeProvider,
                          homeProvider.theBestServers,
                          "The Best",
                        ),
                        _buildServerList(
                          homeProvider,
                          homeProvider.obsoleteServers,
                          "Obsolete",
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 1. امضای متد را تغییر بده تا homeProvider را دریافت کند
  Widget _buildServerList(
    HomeProvider homeProvider,
    List<Server> servers,
    String categoryName,
  ) {
    debugPrint(
      "➡️ [ModernServerListScreen] Building list for category: $categoryName with ${servers.length} items.",
    );
    if (servers.isEmpty) {
      return const Center(child: Text("No servers in this category."));
    }

    return ListView.separated(
      itemCount: servers.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (ctx, index) {
        final server = servers[index];
        debugPrint("  - [ListView] Building item: ${server.name}");

        // 2. مقدار isSelected را مستقیماً از homeProvider محاسبه کن
        final bool isSelected =
            homeProvider.manualSelectedServer?.id == server.id;

        return ServerListItem(
          server: server,
          isSelected: isSelected, //  <--- ✅ مشکل حل شد
          onTap: () {
            debugPrint("👆 [ModernServerListScreen] Tapped on: ${server.name}");
            // برای فراخوانی توابع، از read استفاده کن یا از همان homeProvider که از Consumer آمده
            context.read<HomeProvider>().selectServer(server);
            Navigator.of(context).pop();
          },
          onToggleFavorite: () {
            debugPrint(
              "👆 [ModernServerListScreen] Toggled favorite for: ${server.name}",
            );
            context.read<HomeProvider>().toggleFavorite(server);
          },
          onDelete: () {
            debugPrint(
              "👆 [ModernServerListScreen] Tapped delete for: ${server.name}",
            );
            context.read<HomeProvider>().deleteServer(server);
          },
          onTestSpeed: () {
            debugPrint(
              "👆 [ModernServerListScreen] Tapped speed test for: ${server.name}",
            );
            context.read<HomeProvider>().handleSpeedTest(server);
          },
          onTestPing: () {
            debugPrint(
              "👆 [ModernServerListScreen] Tapped ping test for: ${server.name}",
            );
            // For now, we'll just log this action
            // In a real implementation, you would trigger a ping test
          },
          onTestStability: () {
            debugPrint(
              "👆 [ModernServerListScreen] Tapped stability test for: ${server.name}",
            );
            // For now, we'll just log this action
            // In a real implementation, you would trigger a stability test
          },
        );
      },
    );
  }
}
