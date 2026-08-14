import 'package:flutter/material.dart';
import '../models/vpn_config_with_metrics.dart';
import 'scale_on_tap.dart';

class ConfigCard extends StatelessWidget {
  final VpnConfigWithMetrics config;
  final bool isSelected;
  final bool isTesting;
  final VoidCallback onTap;
  final VoidCallback onTestLatency;
  final VoidCallback onTestSpeed;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;

  const ConfigCard({
    super.key,
    required this.config,
    required this.isSelected,
    required this.isTesting,
    required this.onTap,
    required this.onTestLatency,
    required this.onTestSpeed,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.blueAccent.withValues(alpha: 0.5)
                : const Color(0xFF2A2A2A),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.2),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: ScaleOnTap(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  _CountryFlag(countryCode: config.countryCode),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ConfigInfo(config: config, isTesting: isTesting),
                  ),
                  const SizedBox(width: 12),
                  _ConfigActions(
                    config: config,
                    isSelected: isSelected,
                    onTestLatency: onTestLatency,
                    onTestSpeed: onTestSpeed,
                    onToggleFavorite: onToggleFavorite,
                    onDelete: onDelete,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountryFlag extends StatelessWidget {
  final String? countryCode;

  const _CountryFlag({required this.countryCode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
      ),
      child: Center(child: _buildCountryFlag(countryCode)),
    );
  }

  Widget _buildCountryFlag(String? countryCode) {
    if (countryCode == null) {
      return Icon(Icons.public, size: 20, color: Colors.grey[400]);
    }

    final flag = _countryCodeToFlag(countryCode);
    if (flag.isNotEmpty) {
      return Text(flag, style: const TextStyle(fontSize: 20));
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.blueAccent.withValues(alpha: 0.3),
            Colors.indigoAccent.withValues(alpha: 0.2),
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
}

class _ConfigInfo extends StatelessWidget {
  final VpnConfigWithMetrics config;
  final bool isTesting;

  const _ConfigInfo({required this.config, required this.isTesting});

  @override
  Widget build(BuildContext context) {
    return Column(
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
                  fontWeight:
                      config.isFavorite ? FontWeight.bold : FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (config.isFavorite)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.star, size: 14, color: Colors.amber),
              ),
          ],
        ),

        const SizedBox(height: 4),

        // Metrics
        Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              layoutBuilder:
                  (Widget? currentChild, List<Widget> previousChildren) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: isTesting
                  ? Row(
                      key: const ValueKey('testing'),
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.orangeAccent,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
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
                  : Row(
                      key: const ValueKey('metrics'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (config.currentPing > 0 || config.currentPing == -1)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (config.currentPing == -1
                                      ? Colors.redAccent
                                      : getPingColor(config.currentPing))
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: (config.currentPing == -1
                                        ? Colors.redAccent
                                        : getPingColor(config.currentPing))
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              config.currentPing == -1
                                  ? 'Timeout'
                                  : '${config.currentPing}ms',
                              style: TextStyle(
                                color: config.currentPing == -1
                                    ? Colors.redAccent
                                    : getPingColor(config.currentPing),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (config.currentPing > 0 || config.currentPing == -1)
                          const SizedBox(width: 6),
                        if (config.currentSpeed > 0)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.greenAccent.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Text(
                              '${config.currentSpeed.toStringAsFixed(1)}Mbps',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8, right: 8),
                          decoration: BoxDecoration(
                            color: getTierColor(config.tier),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: getTierBorderColor(config.tier),
                              width: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              layoutBuilder:
                  (Widget? currentChild, List<Widget> previousChildren) {
                return Stack(
                  alignment: Alignment.centerRight,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: isTesting
                  ? const SizedBox.shrink(key: ValueKey('empty_score'))
                  : Text(
                      'Score: ${config.calculatedScore.toStringAsFixed(1)}',
                      key: const ValueKey('score'),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfigActions extends StatelessWidget {
  final VpnConfigWithMetrics config;
  final bool isSelected;
  final VoidCallback onTestLatency;
  final VoidCallback onTestSpeed;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDelete;

  const _ConfigActions({
    required this.config,
    required this.isSelected,
    required this.onTestLatency,
    required this.onTestSpeed,
    required this.onToggleFavorite,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Latency Test button
        Tooltip(
          message: 'Latency Test',
          child: ScaleOnTap(
            onTap: onTestLatency,
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(
                Icons.network_check,
                size: 20,
                color: Colors.blueAccent,
              ),
            ),
          ),
        ),

        // Speed Test button
        Tooltip(
          message: 'Test Speed',
          child: ScaleOnTap(
            onTap: onTestSpeed,
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.speed, size: 20, color: Colors.greenAccent),
            ),
          ),
        ),

        // Favorite button
        Tooltip(
          message: 'Toggle Favorite',
          child: ScaleOnTap(
            onTap: onToggleFavorite,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                config.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 20,
                color: config.isFavorite ? Colors.amber : Colors.grey[500],
              ),
            ),
          ),
        ),

        // Delete button
        Tooltip(
          message: 'Delete Server',
          child: ScaleOnTap(
            onTap: onDelete,
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.redAccent,
              ),
            ),
          ),
        ),

        // Selection indicator
        AnimatedSwitcher(
          layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
            return Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          duration: const Duration(milliseconds: 300),
          child: isSelected
              ? Container(
                  key: const ValueKey('selected'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                )
              : const SizedBox(
                  key: ValueKey('unselected'),
                  width: 8,
                  height: 8,
                ),
        ),
      ],
    );
  }
}

Color getPingColor(int ping) {
  if (ping < 0) return Colors.grey; // Timeout
  if (ping <= 500) return Colors.green[700]!;
  if (ping <= 1000) return Colors.lightGreen; // Good
  if (ping <= 2000) return Colors.orange; // Fair
  return Colors.red; // Poor
}

Color getTierColor(int tier) {
  switch (tier) {
    case 3:
      return Colors.green;
    case 2:
      return Colors.yellow;
    case 1:
      return Colors.grey;
    default:
      return Colors.red;
  }
}

Color getTierBorderColor(int tier) {
  switch (tier) {
    case 3:
      return Colors.green.shade700;
    case 2:
      return Colors.yellow.shade700;
    case 1:
      return Colors.grey.shade700;
    default:
      return Colors.red.shade700;
  }
}
