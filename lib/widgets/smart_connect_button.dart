import 'package:flutter/material.dart';
import '../services/config_manager.dart';
import '../models/vpn_config_with_metrics.dart';
import '../utils/advanced_logger.dart';
import '../services/ad_service.dart';
import '../services/access_manager.dart';

class SmartConnectButton extends StatefulWidget {
  final double buttonSize;
  final bool showStatus;
  final VoidCallback? onPressed;
  
  const SmartConnectButton({
    super.key,
    this.buttonSize = 200.0,
    this.showStatus = true,
    this.onPressed,
  });
  
  @override
  State<SmartConnectButton> createState() => _SmartConnectButtonState();
}

class _SmartConnectButtonState extends State<SmartConnectButton> {
  bool _isConnecting = false;
  bool _isConnected = false;
  String _connectionStatus = 'Ready';
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Status indicator
        if (widget.showStatus) _buildStatusIndicator(),
        
        const SizedBox(height: 20),
        
        // Big connect button
        GestureDetector(
          onTap: widget.onPressed ?? _handleConnection,
          child: Container(
            width: widget.buttonSize,
            height: widget.buttonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getButtonColor(),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getButtonIcon(),
                  size: widget.buttonSize * 0.3,
                  color: Colors.white,
                ),
                const SizedBox(height: 10),
                Text(
                  _getButtonText(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.buttonSize * 0.1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 20),

        // Quick action buttons - removed since logic is handled at screen level
      ],
    );
  }
  
  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[900]?.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isConnected ? Icons.wifi : Icons.wifi_off,
            color: _isConnected ? Colors.greenAccent : Colors.grey,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            _connectionStatus,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  
  Future<void> _handleConnection() async {
    if (_isConnecting) return;

    // Toggle disconnect
    if (_isConnected) {
      setState(() {
        _isConnected = false;
        _connectionStatus = 'Disconnected';
      });
      // TODO: Implement actual disconnect logic
      return;
    }

    // Check access before proceeding
    final accessManager = AccessManager();
    if (!accessManager.hasAccess) {
      // For the widget's own connection flow, we can't show the same ad sequence
      // as the parent screen, so we'll just show a message
      setState(() {
        _connectionStatus = 'No access. Watching ad for access...';
      });

      // Show a simplified ad flow for the widget's own connection
      // In a real implementation, you might want to have a callback to the parent
      setState(() {
        _connectionStatus = 'Access required. Please use main screen.';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Preparing connection...';
    });

    try {
      final configManager = ConfigManager();

      // Determine which config to use
      VpnConfigWithMetrics? configToUse;

      if (configManager.selectedConfig != null) {
        // If user has selected a server, connect directly to it
        configToUse = configManager.selectedConfig;
        AdvancedLogger.info('[SmartConnect] Using selected config: ${configToUse!.name}');
      } else {
        // If no server selected, run Fastest logic first, then connect
        _connectionStatus = 'Finding fastest server...';
        configToUse = await configManager.runQuickTestOnAllConfigs((log) {
          // Update status with test progress
          if (mounted) {
            setState(() {
              _connectionStatus = log;
            });
          }
        });

        if (configToUse != null) {
          // Select the found config so it's remembered for future connections
          configManager.selectConfig(configToUse);
          AdvancedLogger.info('[SmartConnect] Auto-selected best server: ${configToUse.name} (${configToUse.currentPing}ms)');
        } else {
          AdvancedLogger.info('[SmartConnect] No valid config found after testing');
        }
      }

      if (configToUse == null) {
        setState(() {
          _connectionStatus = 'No valid config found';
          _isConnecting = false;
        });
        return;
      }

      // Update status to connecting
      if (mounted) {
        setState(() {
          _connectionStatus = 'Connecting to ${configToUse?.name ?? "Server"}...';
        });
      }

      // Note: This is simulated connection. Actual VPN connection should be handled by parent screen
      // For widget's own connection, we'll continue to simulate
      await Future.delayed(const Duration(seconds: 2));

      // Update metrics
      configManager.updateConfigMetrics(
        configToUse.id,
        connectionSuccess: true,
      );

      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _connectionStatus = 'Connected to ${configToUse?.name}';
      });

    } catch (e) {
      AdvancedLogger.error('[SmartConnect] Connection failed: $e');
      setState(() {
        _isConnecting = false;
        _connectionStatus = 'Connection failed';
      });
    }
  }
  
  Future<void> _handleQuickConnect() async {
    final configManager = ConfigManager();

    // Fastest button: Only selects the best server, doesn't connect
    if (configManager.allConfigs.isEmpty) {
      setState(() {
        _connectionStatus = 'No configs available';
      });
      return;
    }

    // Run quick test to find the best server
    final bestConfig = await configManager.runQuickTestOnAllConfigs((log) {
      if (mounted) {
        setState(() {
          _connectionStatus = log;
        });
      }
    });

    if (bestConfig != null) {
      configManager.selectConfig(bestConfig); // Only select, don't connect
      setState(() {
        _connectionStatus = 'Best server selected: ${bestConfig.name}';
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Best server selected: ${bestConfig.name} (${bestConfig.currentPing}ms)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      setState(() {
        _connectionStatus = 'No valid config found';
      });
    }
  }
  
  Future<void> _handleFavoriteConnect() async {
    final configManager = ConfigManager();
    final selectedConfig = configManager.selectedConfig;

    if (selectedConfig != null) {
      await configManager.toggleFavorite(selectedConfig.id);

      // Re-fetch the config to ensure we have the LATEST state after the toggle
      final updatedConfig = configManager.getConfigById(selectedConfig.id);
      final isFavorite = updatedConfig?.isFavorite ?? false;
      final message = isFavorite ? "Added to Favorites" : "Removed from Favorites";

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isFavorite ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Show feedback that no server is selected
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("No server selected"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  Color _getButtonColor() {
    if (_isConnecting) return Colors.orange;
    if (_isConnected) return Colors.redAccent;
    return Colors.green;
  }
  
  IconData _getButtonIcon() {
    if (_isConnecting) return Icons.sync;
    if (_isConnected) return Icons.power_settings_new;
    return Icons.power_settings_new;
  }
  
  String _getButtonText() {
    if (_isConnecting) return 'Connecting...';
    if (_isConnected) return 'Disconnect';
    return 'Connect';
  }
}
