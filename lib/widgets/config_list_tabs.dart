import 'package:flutter/material.dart';
import '../services/config_manager.dart';
import '../models/vpn_config_with_metrics.dart';

class ConfigListTabs extends StatefulWidget {
  final Function(VpnConfigWithMetrics)? onConfigSelected;
  final Function(VpnConfigWithMetrics)? onConfigTapped;
  final Function(VpnConfigWithMetrics)? onTestLatency;
  final Function(VpnConfigWithMetrics)? onTestSpeed;
  final Function(VpnConfigWithMetrics)? onTestStability;
  final VoidCallback? onTestAll;
  final VoidCallback? onRefresh;
  final Set<String> testingIds;
  final ScrollController? scrollController; // اضافه کردن این خط

  const ConfigListTabs({
    super.key,
    this.onConfigSelected,
    this.onConfigTapped,
    this.onTestLatency,
    this.onTestSpeed,
    this.onTestStability,
    this.onTestAll,
    this.onRefresh,
    this.testingIds = const {},
    this.scrollController, // اضافه کردن این خط
  });
  
  @override
  State<ConfigListTabs> createState() => _ConfigListTabsState();
}

class _ConfigListTabsState extends State<ConfigListTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ConfigManager _configManager = ConfigManager();
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Add listener to refresh when tab changes
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Show confirmation dialog for deleting all configs
  Future<void> _showDeleteAllConfirmationDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Confirm Delete All', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure? This will clear all configs.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      // Call the delete all configs method
      await _configManager.clearAllData();
      setState(() {}); // Refresh the UI
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Add Test All button in the header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.list, color: Colors.blueAccent, size: 22),
              const SizedBox(width: 12),
              Text(
                'Server Configuration',
                style: TextStyle(
                  color: Colors.grey[100],
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.speed, color: Colors.blueAccent),
                onPressed: widget.onTestAll,
                tooltip: 'Test All Connections',
                splashRadius: 20,
              ),
              IconButton(
                icon: Icon(Icons.delete_forever, color: Colors.redAccent),
                onPressed: _showDeleteAllConfirmationDialog,
                tooltip: 'Delete All Configurations',
                splashRadius: 20,
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: [
                  Colors.blueAccent.withOpacity(0.8),
                  Colors.indigoAccent.withOpacity(0.8),
                ],
              ),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey[400],
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 12,
            ),
            tabs: [
              Tab(
                icon: const Icon(Icons.list, size: 18),
                text: 'All (${_configManager.allConfigs.length})',
              ),
              Tab(
                icon: const Icon(Icons.check_circle, size: 18),
                text: 'Valid (${_configManager.validatedConfigs.length})',
              ),
              Tab(
                icon: const Icon(Icons.star, size: 18),
                text: 'Favs (${_configManager.favoriteConfigs.length})',
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Tab content - replaced TabBarView with direct list rendering to avoid unbounded height constraints
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, child) {
            return ListenableBuilder(
              listenable: ConfigManager(), // Direct singleton access
              builder: (context, child) {
                // Re-fetch the manager to ensure we have the latest ref (though it's singleton)
                final configManager = ConfigManager();
                Widget content;
                switch (_tabController.index) {
                  case 0:
                    content = _buildConfigList(configManager.allConfigs);
                    break;
                  case 1:
                    content = _buildConfigList(configManager.validatedConfigs);
                    break;
                  case 2:
                    content = _buildConfigList(configManager.favoriteConfigs);
                    break;
                  default:
                    content = _buildConfigList(configManager.allConfigs);
                }
                return content;
              },
            );
          },
        ),
      ],
    );
  }
  
  Widget _buildConfigList(List<VpnConfigWithMetrics> configs) {
    if (configs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'No configs available',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use Smart Paste to add configs',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      backgroundColor: const Color(0xFF1A1A1A),
      color: Colors.blueAccent,
      onRefresh: () async {
        setState(() {});
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.builder(
        controller: widget.scrollController, // Use the provided scrollController
        shrinkWrap: true, // Enable shrinkWrap for use in parent ScrollView
        physics: const NeverScrollableScrollPhysics(), // Disable internal scrolling
        padding: const EdgeInsets.all(8),
        itemCount: configs.length,
        itemBuilder: (context, index) {
          final config = configs[index];
          return _buildConfigCard(config);
        },
      ),
    );
  }
  
  Widget _buildConfigCard(VpnConfigWithMetrics config) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _configManager.selectedConfig?.id == config.id
              ? Colors.blueAccent.withOpacity(0.5)
              : const Color(0xFF2A2A2A),
          width: _configManager.selectedConfig?.id == config.id ? 1.5 : 1,
        ),
        boxShadow: _configManager.selectedConfig?.id == config.id
            ? [
                BoxShadow(
                  color: Colors.blueAccent.withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _configManager.selectConfig(config);
            widget.onConfigTapped?.call(config);
            setState(() {});
          },
          borderRadius: BorderRadius.circular(12),
          splashColor: Colors.blueAccent.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Country flag/icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.blueAccent.withOpacity(0.3),
                    ),
                  ),
                  child: Center(
                    child: _buildCountryFlag(config.countryCode),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Config info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              config.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: config.isFavorite
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (config.isFavorite)
                            Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                        ],
                      ),
                      
                      const SizedBox(height: 4),
                      
                      // Metrics
                      Row(
                        children: [
                          if (widget.testingIds.contains(config.id))
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Testing...',
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          else if (config.currentPing > 0 || config.currentPing == -1)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: (config.currentPing == -1 ? Colors.redAccent : _getPingColor(config.currentPing))
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: (config.currentPing == -1 ? Colors.redAccent : _getPingColor(config.currentPing))
                                      .withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                config.currentPing == -1 ? 'Timeout' : '${config.currentPing}ms',
                                style: TextStyle(
                                  color: config.currentPing == -1 ? Colors.redAccent : _getPingColor(config.currentPing),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          
                          if (widget.testingIds.contains(config.id) || config.currentPing > 0 || config.currentPing == -1)
                            const SizedBox(width: 6),

                          if (config.currentSpeed > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.greenAccent.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                '${config.currentSpeed.toStringAsFixed(1)}Mbps',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                          // Tier indicator
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _getTierColor(config.tier),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _getTierBorderColor(config.tier),
                                width: 1,
                              ),
                            ),
                            margin: const EdgeInsets.only(right: 8),
                          ),

                          const Spacer(),

                          Text(
                            'Score: ${config.calculatedScore.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Actions
                Column(
                  children: [
                    // Latency Test button
                    IconButton(
                      icon: Icon(
                        Icons.network_check,
                        size: 20,
                        color: Colors.blueAccent,
                      ),
                      onPressed: () {
                        widget.onTestLatency?.call(config);
                      },
                      tooltip: 'Latency Test',
                      splashRadius: 20,
                    ),

                    // Speed Test button
                    IconButton(
                      icon: Icon(
                        Icons.speed,
                        size: 20,
                        color: Colors.greenAccent,
                      ),
                      onPressed: () {
                        widget.onTestSpeed?.call(config);
                      },
                      tooltip: 'Test Speed (2MB Download)',
                      splashRadius: 20,
                    ),

                    // Stability Test button
                    IconButton(
                      icon: Icon(
                        Icons.analytics_outlined, // Changed to Analytics icon
                        size: 20,
                        color: Colors.orangeAccent,
                      ),
                      onPressed: () {
                        widget.onTestStability?.call(config);
                      },
                      tooltip: 'Analyze Stability',
                      splashRadius: 20,
                    ),

                    // Favorite button
                    IconButton(
                      icon: Icon(
                        config.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 20,
                        color: config.isFavorite ? Colors.amber : Colors.grey[500],
                      ),
                      onPressed: () async {
                        await _configManager.toggleFavorite(config.id);
                        setState(() {});
                      },
                      splashRadius: 20,
                    ),

                    // Delete button with confirmation
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.redAccent,
                      ),
                      onPressed: () async {
                        final confirm = await _showDeleteConfirmationDialog(config);
                        if (confirm && mounted) {
                          final success = await _configManager.deleteConfig(config.id);
                          if (success) {
                            setState(() {
                              // The config will be removed from the list automatically
                            });
                          }
                        }
                      },
                      tooltip: 'Delete Server',
                      splashRadius: 20,
                    ),

                    // Selection indicator
                    if (_configManager.selectedConfig?.id == config.id)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withOpacity(0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildCountryFlag(String? countryCode) {
    if (countryCode == null) {
      return Icon(
        Icons.public,
        size: 20,
        color: Colors.grey[400],
      );
    }
    
    final flag = _countryCodeToFlag(countryCode);
    if (flag.isNotEmpty) {
      return Text(
        flag,
        style: const TextStyle(fontSize: 20),
      );
    }
    
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.blueAccent.withOpacity(0.3),
            Colors.indigoAccent.withOpacity(0.2),
          ],
        ),
      ),
      child: Center(
        child: Text(
          countryCode.length >= 2
              ? countryCode.substring(0, 2).toUpperCase()
              : '??',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey[300],
          ),
        ),
      ),
    );
  }
  
  String _countryCodeToFlag(String countryCode) {
    final flags = {
      'US': '🇺🇸',
      'DE': '🇩🇪',
      'TR': '🇹🇷',
      'IR': '🇮🇷',
      'GB': '🇬🇧',
      'FR': '🇫🇷',
      'JP': '🇯🇵',
      'KR': '🇰🇷',
      'CN': '🇨🇳',
      'RU': '🇷🇺',
      'NL': '🇳🇱',
      'CA': '🇨🇦',
      'AU': '🇦🇺',
      'SG': '🇸🇬',
      'IN': '🇮🇳',
      'BR': '🇧🇷',
      'IT': '🇮🇹',
      'ES': '🇪🇸',
      'SE': '🇸🇪',
      'CH': '🇨🇭',
      'NO': '🇳🇴',
      'FI': '🇫🇮',
      'DK': '🇩🇰',
      'PL': '🇵🇱',
      'CZ': '🇨🇿',
      'HU': '🇭🇺',
      'AT': '🇦🇹',
      'BE': '🇧🇪',
      'IE': '🇮🇪',
      'PT': '🇵🇹',
      'GR': '🇬🇷',
      'RO': '🇷🇴',
      'BG': '🇧🇬',
      'HR': '🇭🇷',
      'SK': '🇸🇰',
      'SI': '🇸🇮',
      'EE': '🇪🇪',
      'LV': '🇱🇻',
      'LT': '🇱🇹',
      'CY': '🇨🇾',
      'LU': '🇱🇺',
      'MT': '🇲🇹',
    };
    
    return flags[countryCode.toUpperCase()] ?? '';
  }
  
  Color _getPingColor(int ping) {
    if (ping < 0) return Colors.grey; // Timeout
    if (ping <= 500) return Colors.green[700]!; // Excellent
    if (ping <= 1000) return Colors.lightGreen!; // Good
    if (ping <= 2000) return Colors.orange!; // Fair
    return Colors.red!; // Poor
  }
  
  void _showConfigDetails(BuildContext context, VpnConfigWithMetrics config) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          config.name,
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('ID', config.id),
              _buildDetailRow('Country', config.countryCode ?? 'Unknown'),
              _buildDetailRow('Ping', '${config.currentPing}ms'),
              _buildDetailRow('Speed', '${config.currentSpeed} Mbps'),
              _buildDetailRow(
                'Success Rate',
                '${(config.successRate * 100).toStringAsFixed(1)}%',
              ),
              _buildDetailRow(
                'Usage Count',
                '${config.deviceMetrics[ConfigManager().currentDeviceId]?.usageCount ?? 0}',
              ),
              _buildDetailRow(
                'Favorite',
                config.isFavorite ? 'Yes' : 'No',
              ),
              const SizedBox(height: 16),
              const Text(
                'Raw Config (first 150 chars):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  config.rawConfig.length > 150
                      ? '${config.rawConfig.substring(0, 150)}...'
                      : config.rawConfig,
                  style: const TextStyle(
                    fontFamily: 'Monospace',
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Colors.blueAccent),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[400],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showDeleteConfirmationDialog(VpnConfigWithMetrics config) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Delete Config?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to remove "${config.name}"?',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    ) ?? false;
  }

  // Helper method to get color based on tier
  Color _getTierColor(int tier) {
    switch (tier) {
      case 3: // Stable/HighSpeed
        return Colors.green; // Green for Tier 3
      case 2: // LowLatency
        return Colors.yellow; // Yellow for Tier 2
      case 1: // Alive
        return Colors.grey; // Grey for Tier 1
      default:
        return Colors.red; // Red for untested/failed
    }
  }

  // Helper method to get border color based on tier
  Color _getTierBorderColor(int tier) {
    switch (tier) {
      case 3: // Stable/HighSpeed
        return Colors.green.shade700; // Darker green for border
      case 2: // LowLatency
        return Colors.yellow.shade700; // Darker yellow for border
      case 1: // Alive
        return Colors.grey.shade700; // Darker grey for border
      default:
        return Colors.red.shade700; // Darker red for border
    }
  }
}