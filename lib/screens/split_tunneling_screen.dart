import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/config_manager.dart';

class SplitTunnelingScreen extends StatefulWidget {
  const SplitTunnelingScreen({super.key});

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen> {
  // Mock data for initial UI verification
  final List<Map<String, String>> _mockApps = [
    {'name': 'Google Chrome', 'package': 'com.android.chrome'},
    {'name': 'WhatsApp', 'package': 'com.whatsapp'},
    {'name': 'Telegram', 'package': 'org.telegram.messenger'},
    {'name': 'Spotify', 'package': 'com.spotify.music'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split Tunneling')),
      body: Consumer<ConfigManager>(
        builder: (context, configManager, child) {
          final bypassedPackages = configManager.splitTunnelingPackages;

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Selected apps will bypass the VPN and connect directly to the internet.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _mockApps.length,
                  itemBuilder: (context, index) {
                    final app = _mockApps[index];
                    final packageName = app['package']!;
                    final isBypassed = bypassedPackages.contains(packageName);

                    return ListTile(
                      leading: const Icon(Icons.android),
                      title: Text(app['name']!),
                      subtitle: Text(packageName),
                      trailing: Switch(
                        value: isBypassed,
                        onChanged: (bool value) {
                          final newList = List<String>.from(bypassedPackages);
                          if (value) {
                            newList.add(packageName);
                          } else {
                            newList.remove(packageName);
                          }
                          configManager.setSplitTunnelingPackages(newList);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
