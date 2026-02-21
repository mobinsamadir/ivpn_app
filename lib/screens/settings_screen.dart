// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart'; // برای دسترسی به ThemeProvider

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // متغیر برای کنترل وضعیت‌های جدید
  bool _killSwitchEnabled = false;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // بخش تنظیمات اتصال
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Connection',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Kill Switch'),
            subtitle: const Text('Block internet if VPN disconnects'),
            value: _killSwitchEnabled,
            onChanged: (bool value) {
              setState(() {
                _killSwitchEnabled = value;
              });
              // TODO: Add logic to handle Kill Switch
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kill Switch logic is not implemented yet.'),
                ),
              );
            },
            secondary: const Icon(Icons.gpp_good_outlined),
          ),
          ListTile(
            leading: const Icon(Icons.splitscreen_outlined),
            title: const Text('Split Tunneling'),
            subtitle: const Text('Choose which apps use the VPN'),
            onTap: () {
              // TODO: Add navigation to a new screen for app selection
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Split Tunneling feature is coming soon!'),
                ),
              );
            },
          ),
          const Divider(),

          // بخش تنظیمات ظاهری
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Appearance',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: themeProvider.themeMode,
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System Default'),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (mode) {
                if (mode != null) {
                  // Update the theme provider
                  if (mode == ThemeMode.dark) {
                    themeProvider.toggleTheme(true);
                  } else if (mode == ThemeMode.light) {
                    themeProvider.toggleTheme(false);
                  } else {
                    // For system theme, we can default to light or dark
                    themeProvider.toggleTheme(false);
                  }
                }
              },
            ),
          ),
          const Divider(),

          // بخش اطلاعات
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'About',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            trailing: Text('1.0.0'),
          ),
        ],
      ),
    );
  }
}
