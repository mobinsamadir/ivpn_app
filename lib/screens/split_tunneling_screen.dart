import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_info.dart';
import '../services/config_manager.dart';
import '../services/native_vpn_service.dart';
import '../widgets/scale_on_tap.dart';

enum AppFilterMode { all, iranian, bypassed }

class SplitTunnelingScreen extends StatefulWidget {
  const SplitTunnelingScreen({super.key});

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen> {
  final TextEditingController _searchController = TextEditingController();
  final NativeVpnService _nativeVpnService = NativeVpnService();

  List<InstalledApp> _allApps = [];
  bool _isLoading = true;
  String _searchQuery = '';
  AppFilterMode _filterMode = AppFilterMode.all;

  @override
  void initState() {
    super.initState();
    _loadInstalledApps();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledApps() async {
    setState(() => _isLoading = true);
    try {
      final apps = await _nativeVpnService.getInstalledApps();
      if (mounted) {
        setState(() {
          _allApps = apps;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _bypassAllIranianApps(ConfigManager configManager) {
    final iranianPackages =
        _allApps.where((app) => app.isIranianApp).map((e) => e.packageName).toSet();

    final currentSet = Set<String>.from(configManager.splitTunnelingPackages);
    currentSet.addAll(iranianPackages);

    configManager.setSplitTunnelingPackages(currentSet.toList());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${iranianPackages.length} Iranian apps set to bypass VPN',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearAllBypassed(ConfigManager configManager) {
    configManager.setSplitTunnelingPackages([]);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cleared all split tunneling rules'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<InstalledApp> _getFilteredApps(List<String> bypassedPackages) {
    return _allApps.where((app) {
      // 1. Search Query
      if (_searchQuery.isNotEmpty) {
        final matchesName = app.name.toLowerCase().contains(_searchQuery);
        final matchesPkg =
            app.packageName.toLowerCase().contains(_searchQuery);
        if (!matchesName && !matchesPkg) return false;
      }

      // 2. Filter Mode
      switch (_filterMode) {
        case AppFilterMode.iranian:
          return app.isIranianApp;
        case AppFilterMode.bypassed:
          return bypassedPackages.contains(app.packageName);
        case AppFilterMode.all:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final configManager = Provider.of<ConfigManager>(context);
    final bypassedPackages = configManager.splitTunnelingPackages;
    final iranianAppsCount = _allApps.where((a) => a.isIranianApp).length;
    final filteredApps = _getFilteredApps(bypassedPackages);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Split Tunneling'),
        actions: [
          if (bypassedPackages.isNotEmpty)
            IconButton(
              tooltip: 'Clear All',
              icon: const Icon(Icons.clear_all),
              onPressed: () => _clearAllBypassed(configManager),
            ),
          IconButton(
            tooltip: 'Refresh Apps',
            icon: const Icon(Icons.refresh),
            onPressed: _loadInstalledApps,
          ),
        ],
      ),
      body: Column(
        children: [
          // Informational Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.blueGrey.withValues(alpha: 0.15),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.lightBlueAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Selected apps route directly through regular internet without going through the VPN.',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search Box
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search apps or packages...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Filter Chips & Quick Preset Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text('All (${_allApps.length})'),
                          selected: _filterMode == AppFilterMode.all,
                          onSelected: (val) {
                            if (val) setState(() => _filterMode = AppFilterMode.all);
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text('Iranian ($iranianAppsCount)'),
                          selected: _filterMode == AppFilterMode.iranian,
                          onSelected: (val) {
                            if (val) {
                              setState(() => _filterMode = AppFilterMode.iranian);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text('Bypassed (${bypassedPackages.length})'),
                          selected: _filterMode == AppFilterMode.bypassed,
                          onSelected: (val) {
                            if (val) {
                              setState(() => _filterMode = AppFilterMode.bypassed);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Quick Action Banner for Iranian Apps
          if (iranianAppsCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ScaleOnTap(
                onTap: () => _bypassAllIranianApps(configManager),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        color: Colors.greenAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bypass all Iranian & banking apps in 1-tap',
                          style: TextStyle(
                            color: Colors.greenAccent[100],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.check_circle_outline,
                        color: Colors.greenAccent,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const Divider(height: 12),

          // App List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text(
                          'Scanning installed applications...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : filteredApps.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No matching apps found'
                              : 'No apps available',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredApps.length,
                        itemBuilder: (context, index) {
                          final app = filteredApps[index];
                          final isBypassed =
                              bypassedPackages.contains(app.packageName);

                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: app.iconBytes != null
                                  ? Image.memory(
                                      app.iconBytes!,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 40,
                                      height: 40,
                                      color: Colors.grey[800],
                                      child: const Icon(
                                        Icons.android,
                                        color: Colors.white60,
                                      ),
                                    ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    app.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (app.isIranianApp)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'IR App',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              app.packageName,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Switch(
                              value: isBypassed,
                              activeThumbColor: Colors.greenAccent,
                              onChanged: (val) {
                                configManager.toggleSplitTunnelingPackage(
                                  app.packageName,
                                );
                              },
                            ),
                            onTap: () {
                              configManager.toggleSplitTunnelingPackage(
                                app.packageName,
                              );
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
