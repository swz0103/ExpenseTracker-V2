import 'channel.dart';

/// Starts the background job that delivers the backups left in the
/// outbox (`BackupWorker.kt`), or stops it with `on: false`.
Future<void> androidBackgroundBackups({required bool on}) =>
    platformChannel.invokeMethod<void>('backgroundBackups', {'on': on});
