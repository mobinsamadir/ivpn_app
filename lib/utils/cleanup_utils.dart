import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import '../utils/advanced_logger.dart';
import '../utils/cancellable_operation.dart';

class CleanupUtils {
  /// Truncates the box.log file if it exceeds 2MB and deletes downloaded APKs
  static Future<void> truncateLogsAndOldApks() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final filesDir = await getApplicationDocumentsDirectory();

      // Check log file in both cache and files
      for (final dir in [cacheDir, filesDir]) {
        final logFile = File('${dir.path}/box.log');
        if (await logFile.exists()) {
          final size = await logFile.length();
          if (size > 2 * 1024 * 1024) { // 2 MB
            AdvancedLogger.info("Truncating box.log (size: ${size / 1024 / 1024} MB)");
            await logFile.writeAsString(""); // Clear the log file
          }
        }

        // Delete any downloaded .apk files
        final apkFiles = dir.listSync().where((e) => e.path.endsWith('.apk'));
        for (final apk in apkFiles) {
          if (apk is File) {
            AdvancedLogger.info("Deleting old APK: ${apk.path}");
            await apk.delete();
          }
        }
      }
    } catch (e) {
      AdvancedLogger.warn("Cleanup failed: $e");
    }
  }

  static final Map<String, List<Object>> _jobResources = {};
  static final Map<String, CancelToken> _activeTokens = {};

  /// Register a job and its cancellation token
  static void registerJob(String jobId, CancelToken token) {
    _activeTokens[jobId] = token;
    _jobResources[jobId] = [];
  }

  /// Register a resource (Process, HttpClient, etc.) to a job
  static void registerResource(String jobId, Object resource) {
    if (_jobResources.containsKey(jobId)) {
      _jobResources[jobId]!.add(resource);
      AdvancedLogger.debug(
        '[Cleanup] Registered ${resource.runtimeType} to job $jobId',
      );
    }
  }

  /// Cleanup all resources associated with a specific job
  static Future<void> cleanupJobResources(String jobId) async {
    AdvancedLogger.info('[Cleanup] Starting cleanup for job: $jobId');

    final resources = _jobResources.remove(jobId);
    final token = _activeTokens.remove(jobId);

    if (token != null && !token.isCancelled) {
      token.cancel(CancelReason.system);
    }

    if (resources != null) {
      for (final resource in resources) {
        await _disposeResource(resource);
      }
    }
  }

  /// Direct disposal of a single resource
  static Future<void> _disposeResource(Object resource) async {
    try {
      if (resource is Process) {
        AdvancedLogger.warn('[Cleanup] Killing process: ${resource.pid}');
        resource.kill(ProcessSignal.sigkill);
      } else if (resource is HttpClient) {
        AdvancedLogger.info('[Cleanup] Closing HttpClient');
        resource.close(force: true);
      } else if (resource is Timer) {
        AdvancedLogger.info('[Cleanup] Cancelling Timer');
        resource.cancel();
      } else if (resource is StreamSubscription) {
        AdvancedLogger.info('[Cleanup] Cancelling Subscription');
        await resource.cancel();
      }
    } catch (e) {
      AdvancedLogger.error('[Cleanup] Error disposing resource: $e');
    }
  }

  /// Global emergency cleanup for crashes or app exit
  static Future<void> emergencyCleanup() async {
    AdvancedLogger.error('[Cleanup] EMERGENCY CLEANUP TRIGGERED');

    // Cleanup all known jobs
    final jobIds = _jobResources.keys.toList();
    for (final id in jobIds) {
      await cleanupJobResources(id);
    }

    // Force kill common test processes just in case
    if (Platform.isWindows) {
      try {
        await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']);
        AdvancedLogger.info('[Cleanup] Flushed sing-box processes.');
      } catch (_) {}
    }

    _jobResources.clear();
    _activeTokens.clear();
  }
}
