import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../utils/advanced_logger.dart';

class UpdateDialog extends StatefulWidget {
  final String version;
  final String releaseNotes;
  final String downloadUrl;
  final VoidCallback? onUpdate;

  const UpdateDialog({
    super.key,
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    this.onUpdate,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  String? _errorMessage;

  Future<String> _determineDownloadUrl() async {
    const String baseUrl = 'https://github.com/mobinsamadir/ivpn_app/releases/latest/download';
    if (Platform.isWindows) {
      return '$baseUrl/ivpn-windows.zip';
    }

    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final primaryAbi = androidInfo.supportedAbis.isNotEmpty
            ? androidInfo.supportedAbis.first.toLowerCase()
            : '';

        if (primaryAbi.contains('x86_64')) {
          return '$baseUrl/iVPN-x86_64-release.apk';
        } else if (primaryAbi.contains('arm64-v8a')) {
          return '$baseUrl/iVPN-arm64-v8a-release.apk';
        } else if (primaryAbi.contains('armeabi-v7a')) {
          return '$baseUrl/iVPN-armeabi-v7a-release.apk';
        }
      } catch (e) {
        AdvancedLogger.warn('[InAppUpdate] Could not detect ABI: $e');
      }

      if (widget.downloadUrl.isNotEmpty && widget.downloadUrl.endsWith('.apk')) {
        return widget.downloadUrl;
      }
      return '$baseUrl/iVPN-release.apk';
    }

    return widget.downloadUrl;
  }

  Future<void> _startUpdate() async {
    widget.onUpdate?.call();
    final targetUrl = await _determineDownloadUrl();
    try {
      final uri = Uri.parse(targetUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && widget.downloadUrl.isNotEmpty) {
        await launchUrl(Uri.parse(widget.downloadUrl), mode: LaunchMode.externalApplication);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      AdvancedLogger.error('[UpdateDialog] Launch URL error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not open download link: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update,
                    color: Colors.blueAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New Update Available',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Version ${widget.version}',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Release Notes
            const Text(
              'What\'s New:',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: widget.releaseNotes,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      h1: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      h2: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      h3: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      listBullet: const TextStyle(color: Colors.white70),
                      strong: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      a: const TextStyle(
                        color: Colors.blueAccent,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),


            // Error Notice
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Later',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _startUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Download Update'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
