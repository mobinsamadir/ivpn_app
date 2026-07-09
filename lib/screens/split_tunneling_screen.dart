import 'package:flutter/material.dart';

class SplitTunnelingScreen extends StatefulWidget {
  const SplitTunnelingScreen({super.key});

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen> {
  // Hardcoded list of dummy apps for testing/UI building
  final List<Map<String, dynamic>> _dummyApps = [
    {
      'name': 'Telegram',
      'package': 'org.telegram.messenger',
      'icon': Icons.telegram,
      'isBypassed': false,
    },
    {
      'name': 'Banking App',
      'package': 'com.bank.mobile',
      'icon': Icons.account_balance,
      'isBypassed': false,
    },
    {
      'name': 'Chrome',
      'package': 'com.android.chrome',
      'icon': Icons.web,
      'isBypassed': false,
    },
    {
      'name': 'YouTube',
      'package': 'com.google.android.youtube',
      'icon': Icons.video_library,
      'isBypassed': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split Tunneling')),
      body: ListView.builder(
        itemCount: _dummyApps.length,
        itemBuilder: (context, index) {
          final app = _dummyApps[index];
          return ListTile(
            leading: Icon(app['icon'] as IconData),
            title: Text(app['name'] as String),
            subtitle: Text(app['package'] as String),
            trailing: Switch(
              value: app['isBypassed'] as bool,
              onChanged: (bool value) {
                setState(() {
                  _dummyApps[index]['isBypassed'] = value;
                });
              },
            ),
          );
        },
      ),
    );
  }
}
