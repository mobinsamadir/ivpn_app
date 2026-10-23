import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

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

  Future<void> _startInAppUpdate() async {
    widget.onUpdate?.call();
    if (!Platform.isAndroid) {
      _openExternalBrowser();
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Connecting...';
      _errorMessage = null;
    });

    try {
      final targetUrl = await _determineDownloadUrl();
      final tempDir = await getTemporaryDirectory();
      final saveFile = File('${tempDir.path}/ivpn_update.apk');
      if (await saveFile.exists()) {
        try {
          await saveFile.delete();
        } catch (_) {}
      }

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(targetUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Server responded with HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      final sink = saveFile.openWrite();
      int receivedBytes = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (contentLength > 0 && mounted) {
          setState(() {
            _downloadProgress = (receivedBytes / contentLength).clamp(0.0, 1.0);
            final recMb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
            final totalMb = (contentLength / (1024 * 1024)).toStringAsFixed(1);
            _downloadStatus = '$recMb MB / $totalMb MB (${(_downloadProgress * 100).toInt()}%)';
          });
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      if (mounted) {
        setState(() {
          _downloadStatus = 'Opening Installer...';
        });
      }

      const channel = MethodChannel('vpn_control');
      await channel.invokeMethod('installApk', {'filePath': saveFile.path});
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      AdvancedLogger.error('[UpdateDialog] Direct download error: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'In-app download failed: $e. You can use browser download instead.';
        });
      }
    }
  }

  Future<void> _openExternalBrowser() async {
    final targetUrl = await _determineDownloadUrl();
    try {
      final uri = Uri.parse(targetUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && widget.downloadUrl.isNotEmpty) {
        await launchUrl(Uri.parse(widget.downloadUrl), mode: LaunchMode.externalApplication);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not open browser: $e';
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

            // Progress Indicator
            if (_isDownloading) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _downloadProgress > 0 ? _downloadProgress : null,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _downloadStatus,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isDownloading) ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Later',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _openExternalBrowser,
                    icon: const Icon(Icons.open_in_browser, size: 16, color: Colors.white70),
                    label: const Text(
                      'Browser',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _startInAppUpdate,
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
                    label: const Text('Direct Install'),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    icon: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                    ),
                    label: const Text('Downloading...', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
