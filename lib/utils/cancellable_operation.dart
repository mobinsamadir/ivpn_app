import 'dart:async';

/// A wrapper around a [Future] that allows it to be cancelled.
/// Note: This doesn't stop the actual async operation (like a network request) 
/// unless the underlying operation explicitly checks for cancellation.
class CancellableOperation<T> {
  final Completer<T> _completer = Completer<T>();
  bool _isCancelled = false;

  CancellableOperation(Future<T> future) {
    future.then((value) {
      if (!_isCancelled) {
        _completer.complete(value);
      }
    }).catchError((error, stackTrace) {
      if (!_isCancelled) {
        _completer.completeError(error, stackTrace);
      }
    });
  }

  Future<T> get value => _completer.future;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (!_completer.isCompleted) {
      _isCancelled = true;
      _completer.completeError(OperationCancelledException());
    }
  }
}

enum CancelReason { user, timeout, system }

/// A token that can be passed down to nested async operations to check for cancellation.
class CancelToken {
  bool _isCancelled = false;
  CancelReason? _reason;
  final List<VoidCallback> _onCancelCallbacks = [];

  bool get isCancelled => _isCancelled;
  CancelReason? get reason => _reason;
  bool get wasTimeout => _reason == CancelReason.timeout;

  void cancel([CancelReason reason = CancelReason.user]) {
    if (!_isCancelled) {
      _isCancelled = true;
      _reason = reason;
      for (final callback in _onCancelCallbacks) {
        callback();
      }
      _onCancelCallbacks.clear();
    }
  }

  void markAsTimeout() => cancel(CancelReason.timeout);

  void addOnCancel(VoidCallback callback) {
    if (_isCancelled) {
      callback();
    } else {
      _onCancelCallbacks.add(callback);
    }
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw OperationCancelledException(_reason?.toString() ?? 'Cancelled');
    }
  }
}

typedef VoidCallback = void Function();

class OperationCancelledException implements Exception {
  final String message;
  OperationCancelledException([this.message = 'Operation cancelled']);
  
  @override
  String toString() => 'OperationCancelledException: $message';
}
