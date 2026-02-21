import 'package:flutter/material.dart';
import '../models/vpn_config_with_metrics.dart';

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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Colors.blueAccent.withValues(alpha: 0.5)
              : const Color(0xFF2A2A2A),
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Colors.blueAccent.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: Colors.blueAccent.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Country flag/icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.blueAccent.withValues(alpha: 0.3),
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
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.star,
                                size: 14,
                                color: Colors.amber,
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // Metrics
                      Row(
                        children: [
                          if (isTesting)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.orangeAccent),
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
                          else if (config.currentPing > 0 ||
                              config.currentPing == -1)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: (config.currentPing == -1
                                        ? Colors.redAccent
                                        : _getPingColor(config.currentPing))
                                      .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: (config.currentPing == -1
                                          ? Colors.redAccent
                                          : _getPingColor(config.currentPing))
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
                                      : _getPingColor(config.currentPing),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                          if (!isTesting &&
                              (config.currentPing > 0 ||
                                  config.currentPing == -1))
                            const SizedBox(width: 6),

                          if (!isTesting && config.currentSpeed > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.greenAccent.withValues(alpha: 0.3),
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

                          // Tier indicator
                          if (!isTesting)
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
                              margin: const EdgeInsets.only(left: 8, right: 8),
                            ),

                          const Spacer(),

                          if (!isTesting)
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
                      icon: const Icon(
                        Icons.network_check,
                        size: 20,
                        color: Colors.blueAccent,
                      ),
                      onPressed: onTestLatency,
                      tooltip: 'Latency Test',
                      splashRadius: 20,
                    ),

                    // Speed Test button
                    IconButton(
                      icon: const Icon(
                        Icons.speed,
                        size: 20,
                        color: Colors.greenAccent,
                      ),
                      onPressed: onTestSpeed,
                      tooltip: 'Test Speed',
                      splashRadius: 20,
                    ),

                    // Favorite button
                    IconButton(
                      icon: Icon(
                        config.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 20,
                        color:
                            config.isFavorite ? Colors.amber : Colors.grey[500],
                      ),
                      onPressed: onToggleFavorite,
                      splashRadius: 20,
                    ),

                    // Delete button
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.redAccent,
                      ),
                      onPressed: onDelete,
                      tooltip: 'Delete Server',
                      splashRadius: 20,
                    ),

                    // Selection indicator
                    if (isSelected)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withValues(alpha: 0.5),
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

  Color _getPingColor(int ping) {
    if (ping < 0) return Colors.grey; // Timeout
    if (ping <= 500) return Colors.green[700]!;
    if (ping <= 1000) return Colors.lightGreen; // Good
    if (ping <= 2000) return Colors.orange; // Fair
    return Colors.red; // Poor
  }

  Color _getTierColor(int tier) {
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

  Color _getTierBorderColor(int tier) {
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
}
