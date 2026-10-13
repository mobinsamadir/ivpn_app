import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'scale_on_tap.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../utils/advanced_logger.dart';

class UpdateDialog extends StatefulWidget {
  final String version;
  final String releaseNotes;
  final String downloadUrl;

  const UpdateDialog({
    super.key,
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  static const MethodChannel _platformChannel = MethodChannel('com.example.ivpn/vpn');
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';

  Future<void> _startUpdate() async {
    if (widget.downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download URL is not available')),
      );
      return;
    }

    if (!Platform.isAndroid) {
      // On Windows / other platforms, open download URL in external browser
      launchUrl(Uri.parse(widget.downloadUrl), mode: LaunchMode.externalApplication);
      Navigator.of(context).pop();
      return;
    }

    // Android: In-app download and native install
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusText = 'در حال دانلود بروزرسانی...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/update_${widget.version}.apk';
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      final dio = Dio();
      await dio.download(
        widget.downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() {
              _progress = received / total;
              final percent = (_progress * 100).toStringAsFixed(0);
              _statusText = 'در حال دریافت: $percent%';
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _statusText = 'در حال باز کردن نصب‌کننده...';
      });

      AdvancedLogger.info('[InAppUpdate] APK downloaded to $savePath. Prompting install.');

      try {
        await _platformChannel.invokeMethod('installApk', {'filePath': savePath});
        if (mounted) Navigator.of(context).pop();
      } catch (nativeErr) {
        AdvancedLogger.error('[InAppUpdate] Native install error: $nativeErr');
        // Fallback to external browser if native provider failed
        launchUrl(Uri.parse(widget.downloadUrl), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      AdvancedLogger.error('[InAppUpdate] Download failed: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusText = 'خطا در دانلود. انتقال به مرورگر...';
        });
        await Future.delayed(const Duration(seconds: 1));
        launchUrl(Uri.parse(widget.downloadUrl), mode: LaunchMode.externalApplication);
        if (mounted) Navigator.of(context).pop();
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
            const SizedBox(height: 20),

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
                        fontSize: 14,
                        height: 1.4,
                      ),
                      h1: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      h2: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      h3: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
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
            const SizedBox(height: 24),

            if (_isDownloading) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.grey[800],
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _statusText,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Actions
            if (!_isDownloading)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ScaleOnTap(
                    onTap: () => Navigator.of(context).pop(),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Later',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ScaleOnTap(
                    onTap: _startUpdate,
                    child: ElevatedButton.icon(
                      onPressed: _startUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download & Install'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
