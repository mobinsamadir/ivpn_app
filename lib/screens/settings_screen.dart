// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/theme_provider.dart'; // برای دسترسی به ThemeProvider

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  // متغیر برای کنترل وضعیت‌های جدید
  bool _killSwitchEnabled = false;
  bool _isBatteryOptimizationIgnored = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBatteryOptimizationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBatteryOptimizationStatus();
    }
  }

  Future<void> _checkBatteryOptimizationStatus() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (mounted) {
      setState(() {
        _isBatteryOptimizationIgnored = status.isGranted;
      });
    }
  }

  Future<void> _requestBatteryOptimization() async {
    if (_isBatteryOptimizationIgnored) return;

    // Show explanation dialog first
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep VPN Alive'),
        content: const Text(
          'To prevent Android from killing the VPN connection when your screen is off, please disable battery optimizations for this app.\n\n'
          '1. Tap "Open Settings"\n'
          '2. Select "All apps" (if needed)\n'
          '3. Find "iVPN" and select "Don\'t optimize"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (shouldOpenSettings == true) {
      await Permission.ignoreBatteryOptimizations.request();
      // Status will be re-checked in didChangeAppLifecycleState when user returns
    }
  }

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
          ListTile(
            leading: Icon(
              _isBatteryOptimizationIgnored
                  ? Icons.shield
                  : Icons.battery_alert,
              color:
                  _isBatteryOptimizationIgnored ? Colors.green : Colors.orange,
            ),
            title: const Text('Keep VPN Alive'),
            subtitle: Text(
              _isBatteryOptimizationIgnored
                  ? 'Optimizations disabled (Stable)'
                  : 'Prevent background kills (Recommended)',
              style: TextStyle(
                color: _isBatteryOptimizationIgnored
                    ? Colors.green
                    : Colors.orange,
                fontSize: 12,
              ),
            ),
            trailing: _isBatteryOptimizationIgnored
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _isBatteryOptimizationIgnored
                ? null
                : _requestBatteryOptimization,
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
