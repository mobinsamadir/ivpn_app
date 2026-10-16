import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
  static const MethodChannel _platformChannel = MethodChannel('com.example.ivpn/vpn');
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _downloadedApkPath;
  bool _needsPermission = false;
  String? _errorMessage;

  Future<void> _cleanupOldApks(Directory tempDir) async {
    try {
      if (await tempDir.exists()) {
        final entities = await tempDir.list().toList();
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.apk')) {
            try {
              await entity.delete();
              AdvancedLogger.info('[InAppUpdate] Cleaned old cached apk: ${entity.path}');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      AdvancedLogger.warn('[InAppUpdate] Cleanup old apks failed: $e');
    }
  }

  Future<String> _determineDownloadUrl() async {
    const String baseUrl = 'https://github.com/mobinsamadir/ivpn_app/releases/latest/download';
    if (Platform.isWindows) {
      return '$baseUrl/ivpn-windows.zip';
    }

    if (Platform.isAndroid) {
      // Always use Universal APK (iVPN-release.apk). Single-ABI split APKs
      // cause Android PackageInstaller to fail with "App not installed"
      // (INSTALL_FAILED_UPDATE_INCOMPATIBLE) when installed on top of existing installs.
      if (widget.downloadUrl.isNotEmpty && widget.downloadUrl.endsWith('.apk')) {
        return widget.downloadUrl;
      }
      return '$baseUrl/iVPN-release.apk';
    }

    return widget.downloadUrl;
  }

  Future<void> _installApk(String filePath) async {
    try {
      setState(() {
        _statusText = 'Opening installer...';
        _errorMessage = null;
      });
      await _platformChannel.invokeMethod('installApk', {'filePath': filePath});
      if (mounted) Navigator.of(context).pop();
    } on PlatformException catch (e) {
      AdvancedLogger.error('[InAppUpdate] PlatformException during install: ${e.code} - ${e.message}');
      if (e.code == 'PERMISSION_REQUIRED') {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _needsPermission = true;
            _downloadedApkPath = filePath;
            _statusText = 'Unknown app install permission is required.';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _errorMessage = 'Failed to open installer: ${e.message}';
          });
        }
      }
    } catch (e) {
      AdvancedLogger.error('[InAppUpdate] Native install error: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'System error during install: $e';
        });
      }
    }
  }

  Future<void> _startUpdate() async {
    widget.onUpdate?.call();
    if (widget.downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download URL is not available')),
      );
      return;
    }

    if (!Platform.isAndroid) {
      // On Windows / other platforms, open specific platform archive in external browser
      final targetUrl = await _determineDownloadUrl();
      launchUrl(Uri.parse(targetUrl), mode: LaunchMode.externalApplication);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Android: In-app download and native install
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusText = 'Checking device architecture...';
      _needsPermission = false;
      _errorMessage = null;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      await _cleanupOldApks(tempDir);

      final targetUrl = await _determineDownloadUrl();
      final savePath = '${tempDir.path}/iVPN_${widget.version}.apk';

      setState(() {
        _statusText = 'Downloading update...';
      });

      final dio = Dio(
        BaseOptions(
          followRedirects: true,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 10),
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      bool downloadSuccess = false;
      try {
        await dio.download(
          targetUrl,
          savePath,
          onReceiveProgress: (received, total) {
            if (total > 0 && mounted) {
              setState(() {
                _progress = received / total;
                final percent = (_progress * 100).toStringAsFixed(0);
                _statusText = 'Downloading: $percent%';
              });
            }
          },
        );
        downloadSuccess = true;
      } catch (dlErr) {
        AdvancedLogger.warn('[InAppUpdate] ABI download failed ($dlErr), retrying with universal APK...');
        if (targetUrl != widget.downloadUrl) {
          if (mounted) {
            setState(() {
              _progress = 0.0;
              _statusText = 'Downloading standard package...';
            });
          }
          await dio.download(
            widget.downloadUrl,
            savePath,
            onReceiveProgress: (received, total) {
              if (total > 0 && mounted) {
                setState(() {
                  _progress = received / total;
                  final percent = (_progress * 100).toStringAsFixed(0);
                  _statusText = 'Downloading: $percent%';
                });
              }
            },
          );
          downloadSuccess = true;
        } else {
          rethrow;
        }
      }

      final file = File(savePath);
      if (!downloadSuccess || !await file.exists() || await file.length() < 1024 * 1024) {
        throw Exception('Incomplete download or invalid file size.');
      }

      _downloadedApkPath = savePath;
      await _installApk(savePath);
    } catch (e) {
      AdvancedLogger.error('[InAppUpdate] Download failed: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Download error: $e';
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

            // Needs Permission Notice
            if (_needsPermission) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: Colors.amberAccent, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Please grant "Install unknown apps" permission to iVPN, then tap Install.',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

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

            // Progress Bar
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
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Later',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 8),

                  if (_downloadedApkPath != null)
                    ElevatedButton.icon(
                      onPressed: () => _installApk(_downloadedApkPath!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.install_mobile, size: 18),
                      label: const Text('Install Now'),
                    )
                  else
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
                      label: const Text('Update Now'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
