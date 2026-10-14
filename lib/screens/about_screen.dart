import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/config_gist_service.dart';
import '../widgets/scale_on_tap.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchTelegram() async {
    final tg = await ConfigGistService.getTelegramSupport();
    final Uri url = Uri.parse('https://t.me/$tg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About iVPN')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'iVPN',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Version 1.0.0',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const Divider(height: 40),
            const Text(
              'iVPN is a high-speed, secure, and privacy-focused client designed for unrestricted access to the open internet.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 24),

            // Telegram Support Section
            const Text(
              'Support & VIP Dedicated Configs',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ScaleOnTap(
              onTap: _launchTelegram,
              child: ListTile(
                leading: const Icon(Icons.send_rounded, color: Colors.blueAccent),
                title: const Text('Telegram Support'),
                subtitle: const Text('Order dedicated VIP configs or contact support'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
