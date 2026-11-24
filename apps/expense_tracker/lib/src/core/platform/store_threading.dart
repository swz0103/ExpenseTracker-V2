import 'package:storage/storage.dart' show EncryptedDatabase;

import '../diagnostics/error_log.dart';
import '../diagnostics/error_steps.dart';

/// A backup reads the book on a worker through the store's own
/// connection (D41), which SQLite allows only when built with threads
/// and opened serialized. A build without fails as the store opens in
/// debug and tests; a release build keeps a note of it for 診斷 and goes
/// on. Whether the build has threads, [serialized] standing in for the
/// library's own answer in a test.
bool noteStoreThreading({bool? serialized}) {
  final ok = serialized ?? EncryptedDatabase.serialized;
  if (!ok) {
    ErrorLog.instance.record(
      ErrorSteps.storeThreading,
      StateError('SQLite is built without threads'),
    );
  }
  return ok;
}
