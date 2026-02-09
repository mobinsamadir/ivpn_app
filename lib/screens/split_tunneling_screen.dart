// lib/screens/split_tunneling_screen.dart

import 'package:flutter/material.dart';

class SplitTunnelingScreen extends StatefulWidget {
  const SplitTunnelingScreen({super.key});

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen> {
  final List<Map<String, String>> _allApps = [
    {'name': 'Chrome', 'package': 'com.android.chrome'},
    {'name': 'Telegram', 'package': 'org.telegram.messenger'},
    {'name': 'Instagram', 'package': 'com.instagram.android'},
    {'name': 'WhatsApp', 'package': 'com.whatsapp'},
    {'name': 'YouTube', 'package': 'com.google.android.youtube'},
    {'name': 'Spotify', 'package': 'com.spotify.music'},
    {'name': 'Netflix', 'package': 'com.netflix.mediaclient'},
    {'name': 'Gmail', 'package': 'com.google.android.gm'},
    {'name': 'Facebook', 'package': 'com.facebook.katana'},
    {'name': 'Twitter', 'package': 'com.twitter.android'},
    {'name': 'TikTok', 'package': 'com.zhiliaoapp.musically'},
    {'name': 'Snapchat', 'package': 'com.snapchat.android'},
  ];

  List<Map<String, String>> _filteredApps = [];
  final Set<String> _selectedApps = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredApps = _allApps;
  }

  void _filterApps(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredApps = _allApps;
      } else {
        _filteredApps = _allApps
            .where((app) =>
                app['name']!.toLowerCase().contains(query.toLowerCase()) ||
                app['package']!.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Split Tunneling'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: _filterApps,
              decoration: InputDecoration(
                hintText: 'Search apps...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Selected apps will bypass the VPN and use your direct internet connection.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _filteredApps.isEmpty
                ? const Center(
                    child: Text('No apps found'),
                  )
                : ListView.builder(
                    itemCount: _filteredApps.length,
                    itemBuilder: (context, index) {
                      final app = _filteredApps[index];
                      final isSelected = _selectedApps.contains(app['package']);
                      return CheckboxListTile(
                        title: Text(app['name']!),
                        subtitle: Text(app['package']!),
                        secondary: CircleAvatar(
                          backgroundColor: Colors.green.withOpacity(0.1),
                          child: const Icon(Icons.android, color: Colors.green),
                        ),
                        value: isSelected,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              _selectedApps.add(app['package']!);
                            } else {
                              _selectedApps.remove(app['package']!);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
