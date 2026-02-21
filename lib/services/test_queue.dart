import 'dart:async';
import '../utils/advanced_logger.dart';
import '../utils/cancellable_operation.dart';
import '../utils/test_constants.dart';
import '../utils/cleanup_utils.dart';
import 'test_job.dart';
import 'fallback_strategy.dart';

class _QueueItem {
  final Future<void> Function(CancelToken, String) task;
  final String name;
  final Completer<void> completer;
  final String jobId;
  final TestType? type;
  final CancelToken cancelToken;
  final Duration timeout;

  _QueueItem({
    required this.task,
    required this.name,
    required this.completer,
    required this.jobId,
    required this.cancelToken,
    required this.timeout,
    this.type,
  });
}

class TestQueue {
  final String category;
  TestQueue({required this.category});

  final List<_QueueItem> _queue = [];
  _QueueItem? _activeJob;

  bool get isBusy => _activeJob != null;
  int get queueLength => _queue.length;

  Future<void> enqueue(
    Future<void> Function(CancelToken, String) task, {
    String? name,
    Duration? timeout,
    TestType? type,
  }) async {
    final jobId = '${name ?? 'job'}_${DateTime.now().millisecondsSinceEpoch}';
    final cancelToken = CancelToken();
    final jobTimeout = timeout ?? TestTimeouts.speedTestSingle;

    CleanupUtils.registerJob(jobId, cancelToken);

    final completer = Completer<void>();

    final item = _QueueItem(
      task: task,
      name: name ?? 'Unnamed',
      completer: completer,
      jobId: jobId,
      cancelToken: cancelToken,
      timeout: jobTimeout,
      type: type,
    );

    _queue.add(item);
    _processNext();

    return completer.future;
  }

  void cancelAll() {
    AdvancedLogger.warn('[$category] Cancelling ALL jobs in queue');
    if (_activeJob != null) {
      CleanupUtils.cleanupJobResources(_activeJob!.jobId);
    }
    for (final item in _queue) {
      CleanupUtils.cleanupJobResources(item.jobId);
      if (!item.completer.isCompleted) {
        item.completer
            .completeError(OperationCancelledException('Queue cancelled'));
      }
    }
    _queue.clear();
    _activeJob = null;
  }

  Future<void> _processNext() async {
    if (_activeJob != null || _queue.isEmpty) return;

    _activeJob = _queue.removeAt(0);
    final item = _activeJob!;

    final timer = Timer(item.timeout, () async {
      if (!item.completer.isCompleted) {
        AdvancedLogger.warn(
          '[$category] Job "${item.name}" timed out after ${item.timeout}',
          metadata: {'jobId': item.jobId, 'type': item.type?.toString()},
        );

        item.cancelToken.markAsTimeout();
        await CleanupUtils.cleanupJobResources(item.jobId);

        if (item.type != null) {
          TestFallbackStrategy.triggerFallback(
              item.type!, item.jobId, item.cancelToken);
        }

        item.completer.completeError(
          TimeoutException(
              'Job "${item.name}" timed out after ${item.timeout}'),
        );
      }
    });

    try {
      await item.task(item.cancelToken, item.jobId);

      if (!item.completer.isCompleted) {
        item.completer.complete();
      }
    } catch (e) {
      if (!item.completer.isCompleted) {
        item.completer.completeError(e);
      }
      if (e is! OperationCancelledException || !item.cancelToken.wasTimeout) {
        await CleanupUtils.cleanupJobResources(item.jobId);
      }
    } finally {
      timer.cancel();
      _activeJob = null;
      _processNext();
    }
  }

  bool isJobBusy(int index) {
    final search = '#$index';
    if (_activeJob?.name.contains(search) ?? false) return true;
    return _queue.any((t) => t.name.contains(search));
  }
}
