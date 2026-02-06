// lib/widgets/server_list_item.dart

import 'package:flutter/material.dart';
import '../../models/server_model.dart';
import '../../utils/extensions.dart';

class ServerListItem extends StatelessWidget {
  final Server server;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite; // <-- The missing parameter
  final VoidCallback onDelete; // <-- The missing parameter
  final VoidCallback onTestSpeed;

  const ServerListItem({
    super.key,
    required this.server,
    required this.isSelected,
    required this.onTap,
    required this.onToggleFavorite, // <-- Now part of the constructor
    required this.onDelete, // <-- Now part of the constructor
    required this.onTestSpeed,
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
          Text(
            server.status == PingStatus.bad ? "N/A" : "${server.ping} ms",
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          // --- Favorite and Delete Buttons ---
          IconButton(
            icon: Icon(
              server.isFavorite ? Icons.star : Icons.star_border_outlined,
              color: server.isFavorite ? Colors.amber : Colors.grey,
            ),
            onPressed: onToggleFavorite,
            tooltip: 'Toggle Favorite',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: onDelete,
            tooltip: 'Delete Server',
          ),
        ],
      ),
    );
  }
}
