// lib/widgets/home/connection_info_panel.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/server_model.dart'; // <-- این خط اضافه شد
import '../../providers/home_provider.dart';
import '../../utils/extensions.dart';

class ConnectionInfoPanel extends StatelessWidget {
  const ConnectionInfoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final homeProvider = context.watch<HomeProvider>();
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(12.0),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // بخش سرور متصل
            _buildInfoColumn(
              context: context,
              title: "Current Connection",
              serverName: homeProvider.connectedServer?.name ?? "Not Connected",
              ping: homeProvider.connectedServer?.ping,
              status: homeProvider.connectedServer?.status,
              icon: Icons.shield,
              iconColor: homeProvider.isConnected ? Colors.green : Colors.grey,
            ),
            // جداکننده
            Container(height: 60, width: 1, color: Colors.grey.shade300),
            // بخش بهترین سرور
            _buildInfoColumn(
              context: context,
              title: "Best Server",
              serverName: homeProvider.bestPerformingServer?.name ?? "N/A",
              ping: homeProvider.bestPerformingServer?.ping,
              status: homeProvider.bestPerformingServer?.status,
              icon: Icons.auto_awesome,
              iconColor: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn({
    required BuildContext context,
    required String title,
    required String serverName,
    int? ping,
    PingStatus? status, // <-- نوع داده صحیح است
    required IconData icon,
    required Color iconColor,
  }) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            serverName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          if (ping != null && status != null)
            Text(
              // <-- این خط دیگر خطا نمی‌دهد
              status == PingStatus.bad ? "Offline" : "$ping ms",
              style: TextStyle(
                color: status.color,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}
