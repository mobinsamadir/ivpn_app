import 'package:flutter/material.dart';
import '../services/config_manager.dart';
import '../models/vpn_config_with_metrics.dart';
import '../utils/advanced_logger.dart';
import '../services/time_wallet_service.dart';
import '../services/native_vpn_service.dart';
import 'scale_on_tap.dart';

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

class _SmartConnectButtonState extends State<SmartConnectButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConfigManager(),
      builder: (context, child) {
        final configManager = ConfigManager();
        final isConnected = configManager.isConnected;
        final connectionStatus = configManager.connectionStatus;
        final isConnecting =
            connectionStatus.toLowerCase().contains('connecting') ||
                connectionStatus.toLowerCase().contains('finding') ||
                connectionStatus.toLowerCase().contains('preparing') ||
                connectionStatus.toLowerCase().contains('testing');

        if (isConnecting || isConnected) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.value = 0.0;
        }

        final bool hasConfigs = configManager.validatedConfigs.isNotEmpty ||
            configManager.allConfigs.isNotEmpty;
        final bool isButtonDisabled =
            !hasConfigs && !isConnecting && !isConnected;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.showStatus)
              _buildStatusIndicator(isConnected, connectionStatus),
            const SizedBox(height: 20),
            ScaleOnTap(
              onTap: isButtonDisabled
                  ? null
                  : (widget.onPressed ??
                      () => _handleConnection(configManager)),
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: child,
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  width: widget.buttonSize,
                  height: widget.buttonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _getButtonGradient(
                      isConnected,
                      isConnecting,
                      isButtonDisabled,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _getButtonGlowColor(
                          isConnected,
                          isConnecting,
                          isButtonDisabled,
                        ),
                        blurRadius: isConnecting || isConnected ? 25 : 15,
                        spreadRadius: isConnecting || isConnected ? 8 : 2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: isConnecting
                            ? SizedBox(
                                key: const ValueKey('connecting'),
                                width: widget.buttonSize * 0.3,
                                height: widget.buttonSize * 0.3,
                                child: const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : Icon(
                                key: const ValueKey('icon'),
                                _getButtonIcon(
                                  isConnected,
                                  isConnecting,
                                  isButtonDisabled,
                                ),
                                size: widget.buttonSize * 0.35,
                                color: isButtonDisabled
                                    ? Colors.white54
                                    : Colors.white,
                              ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        layoutBuilder: (Widget? currentChild,
                            List<Widget> previousChildren) {
                          return Stack(
                            alignment: Alignment.centerLeft,
                            children: <Widget>[
                              ...previousChildren,
                              if (currentChild != null) currentChild,
                            ],
                          );
                        },
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _getButtonText(
                            isConnected,
                            isConnecting,
                            isButtonDisabled,
                          ),
                          key: ValueKey(
                            _getButtonText(
                              isConnected,
                              isConnecting,
                              isButtonDisabled,
                            ),
                          ),
                          style: TextStyle(
                            color: isButtonDisabled
                                ? Colors.white54
                                : Colors.white,
                            fontSize: widget.buttonSize * 0.1,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildStatusIndicator(bool isConnected, String status) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.tealAccent.withValues(alpha: 0.1)
            : Colors.grey[900]?.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected
              ? Colors.tealAccent.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConnected ? Icons.check_circle : Icons.wifi_off,
            color: isConnected ? Colors.tealAccent : Colors.grey,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              color: isConnected ? Colors.tealAccent : Colors.white,
              fontSize: 14,
              fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleConnection(ConfigManager configManager) async {
    if (configManager.isConnected) {
      try {
        await NativeVpnService().disconnect();
        await configManager.stopAllOperations();
      } catch (e) {
        AdvancedLogger.error('[SmartConnect] Failed to disconnect: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to disconnect: $e')));
        }
      }
      return;
    }

    final accessManager = TimeWalletService();
    if (!accessManager.hasTime) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access required. Please use main screen.'),
          ),
        );
      }
      return;
    }

    configManager.setConnected(false, status: 'Preparing connection...');

    try {
      VpnConfigWithMetrics? configToUse;

      if (configManager.selectedConfig != null) {
        configToUse = configManager.selectedConfig;
        AdvancedLogger.info(
          '[SmartConnect] Using selected config: ${configToUse!.name}',
        );
      } else {
        configManager.setConnected(false, status: 'Finding fastest server...');
        configToUse = await configManager.getBestConfig();

        if (configToUse != null) {
          configManager.selectConfig(configToUse);
          AdvancedLogger.info(
            '[SmartConnect] Auto-selected best server: ${configToUse.name} (${configToUse.currentPing}ms)',
          );
        } else {
          AdvancedLogger.info(
            '[SmartConnect] No valid config found after testing',
          );
        }
      }

      if (configToUse == null) {
        configManager.setConnected(false, status: 'No valid config found');
        return;
      }

      configManager.setConnected(
        false,
        status: 'Connecting to ${configToUse.name}...',
      );

      await NativeVpnService().connect(configToUse.rawConfig);
    } catch (e) {
      AdvancedLogger.error('[SmartConnect] Connection failed: $e');
      if (mounted) {
        configManager.setConnected(false, status: 'Connection failed');
      }
    }
  }

  Gradient _getButtonGradient(
    bool isConnected,
    bool isConnecting,
    bool isDisabled,
  ) {
    if (isDisabled) {
      return const LinearGradient(
        colors: [Color(0xFF374151), Color(0xFF1F2937)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (isConnecting) {
      return const LinearGradient(
        colors: [Color(0xFFF2994A), Color(0xFFF2C94C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (isConnected) {
      // Changed from RED to TEAL/GREEN gradient
      return const LinearGradient(
        colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    // Disconnected (Greyish blue)
    return const LinearGradient(
      colors: [Color(0xFF4A5568), Color(0xFF2D3748)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Color _getButtonGlowColor(
    bool isConnected,
    bool isConnecting,
    bool isDisabled,
  ) {
    if (isDisabled) return Colors.transparent;
    if (isConnecting) return const Color(0xFFF2994A).withValues(alpha: 0.5);
    if (isConnected) return const Color(0xFF38EF7D).withValues(alpha: 0.5);
    return Colors.black.withValues(alpha: 0.3);
  }

  IconData _getButtonIcon(
    bool isConnected,
    bool isConnecting,
    bool isDisabled,
  ) {
    if (isDisabled) return Icons.hourglass_empty;
    if (isConnecting) return Icons.sync;
    if (isConnected) return Icons.power_settings_new; // Connected icon
    return Icons.power_settings_new;
  }

  String _getButtonText(bool isConnected, bool isConnecting, bool isDisabled) {
    if (isDisabled) return 'WAITING';
    if (isConnecting) return 'CONNECTING';
    if (isConnected) return 'CONNECTED';
    return 'CONNECT';
  }
}
