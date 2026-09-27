import 'dart:io';

/// Cancels lock acquisition only. Once acquired, the operation runs to a known
/// commit/recovery outcome; this token must not imply rollback after publication.
final class LockWaitCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

final class LockWaitExpired implements Exception {}

final class LockWaitAborted implements Exception {}

Future<void> acquireLifecycleLock(
  RandomAccessFile file, {
  required Duration timeout,
  LockWaitCancellation? cancellation,
}) async {
  if (timeout.isNegative) throw ArgumentError.value(timeout, 'timeout');
  final elapsed = Stopwatch()..start();
  var attempted = false;
  while (true) {
    if (cancellation?.isCancelled ?? false) throw LockWaitAborted();
    if (attempted && elapsed.elapsed >= timeout) throw LockWaitExpired();
    attempted = true;
    try {
      await file.lock(FileLock.exclusive);
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      final contention = Platform.isWindows
          ? code == 33
          : (Platform.isLinux || Platform.isAndroid) &&
                (code == 11 || code == 13);
      if (!contention) rethrow;
      final remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) throw LockWaitExpired();
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 25)
            ? remaining
            : const Duration(milliseconds: 25),
      );
      continue;
    }
    // Handle cancellation racing the asynchronous acquisition. Never leak a
    // late-acquired lock or open the catalog after this waiting phase failed.
    if (cancellation?.isCancelled ?? false) {
      await file.unlock();
      throw LockWaitAborted();
    }
    if (timeout != Duration.zero && elapsed.elapsed > timeout) {
      await file.unlock();
      throw LockWaitExpired();
    }
    return;
  }
}
