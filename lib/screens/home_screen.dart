// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'modern_server_list_screen.dart';
import '../providers/home_provider.dart';
import '../widgets/home/connection_status_panel.dart';
import '../widgets/home/connection_info_panel.dart';
import '../utils/add_server_dialog.dart';
import 'settings_screen.dart';
import 'about_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showServerList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ModernServerListScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<HomeProvider>().isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text("iVPN"),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Server or Subscription',
            onPressed: () {
              showAddServerDialog(context);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Update Server List',
                    onPressed: () {
                      context.read<HomeProvider>().loadServersFromUrl();
                    },
                  ),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.green),
              child: Text('iVPN Menu',
                  style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SettingsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('درباره ما'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const AboutScreen()));
              },
            ),
          ],
        ),
      ),
      // --- FIX STARTS HERE ---
      // We wrap the body in a LayoutBuilder to get the screen height constraints
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // Allows scrolling if content is too tall
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // Forces the content to be at least as tall as the screen
                  // This allows 'Spacer' to work inside a ScrollView!
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 20), // Top spacing
                      const ConnectionStatusPanel(),
                      const Spacer(), // Pushes content apart dynamically
                      
                      // Server Selection Button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: ListTile(
                          onTap: () => _showServerList(context),
                          leading: const Icon(Icons.location_on_outlined),
                          title: const Text("Select Location",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      const ConnectionInfoPanel(),
                      
                      const Spacer(), // Pushes content apart dynamically
                      
                      // Log Text (Conditional)
                      if (context.watch<HomeProvider>().logPath.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: SelectableText(
                            "Log: ${context.watch<HomeProvider>().logPath}",
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 20), // Bottom spacing
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      // --- FIX ENDS HERE ---
    );
  }
}