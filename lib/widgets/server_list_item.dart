// lib/widgets/server_list_item.dart

import 'package:flutter/material.dart';
import '../models/server_model.dart';
import '../utils/extensions.dart';

class ServerListItem extends StatelessWidget {
  final Server server;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite; // <-- The missing parameter
  final VoidCallback onDelete; // <-- The missing parameter
  final VoidCallback onTestSpeed;
  final VoidCallback onTestPing;
  final VoidCallback onTestStability;
  final VoidCallback onTestLatency;
  final VoidCallback onTestSpeedTest;
  final VoidCallback onTestStabilityTest;
  final bool isTesting;

  const ServerListItem({
    super.key,
    required this.server,
    required this.isSelected,
    required this.onTap,
    required this.onToggleFavorite, // <-- Now part of the constructor
    required this.onDelete, // <-- Now part of the constructor
    required this.onTestSpeed,
    required this.onTestPing,
    required this.onTestStability,
    required this.onTestLatency,
    required this.onTestSpeedTest,
    required this.onTestStabilityTest,
    this.isTesting = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = server.status.color;
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      tileColor: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : null,
      leading: Icon(Icons.public, color: statusColor),
      title: Text(server.name, overflow: TextOverflow.ellipsis),
      subtitle: server.downloadSpeed > 0
          ? Text(
              "Speed: ${server.downloadSpeed.toStringAsFixed(2)} Mbps",
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTesting)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  "Testing...",
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            )
          else
            Text(
              server.ping == -1 ? "Timeout" : "${server.ping} ms",
              style: TextStyle(
                color: server.ping == -1 ? Colors.red : statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(width: 4),
          // --- Latency Test Button ---
          IconButton(
            icon: Icon(
              Icons.network_check,
              color: Colors.grey[600],
              size: 20,
            ),
            onPressed: onTestLatency,
            tooltip: 'Latency Test',
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          // --- Speed Test Button ---
          IconButton(
            icon: Icon(
              Icons.speed,
              color: Colors.grey[600],
              size: 20,
            ),
            onPressed: onTestSpeedTest,
            tooltip: '30s Speed Test',
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          // --- Stability Test Button ---
          IconButton(
            icon: Icon(
              Icons.health_and_safety,
              color: Colors.grey[600],
              size: 20,
            ),
            onPressed: onTestStabilityTest,
            tooltip: 'Stability Test',
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          // --- Favorite Button ---
          IconButton(
            icon: Icon(
              server.isFavorite ? Icons.star : Icons.star_border_outlined,
              color: server.isFavorite ? Colors.amber : Colors.grey,
            ),
            onPressed: onToggleFavorite,
            tooltip: 'Toggle Favorite',
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          // --- Delete Button ---
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: Colors.redAccent,
              size: 20,
            ),
            onPressed: onDelete, // The parent widget should handle the confirmation
            tooltip: 'Delete Server',
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
