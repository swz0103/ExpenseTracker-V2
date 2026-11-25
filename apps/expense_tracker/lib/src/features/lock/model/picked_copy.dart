import 'dart:io';

import '../../../core/diagnostics/error_log.dart';
import '../../../core/diagnostics/error_steps.dart';

/// Deletes the copy of a chosen backup at [path] once it is not needed:
/// after it was restored, or when the lock screen goes. One that cannot
/// be deleted is noted, and deleted at the next start.
void forgetPickedCopy(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException catch (error) {
    // Deleted at the next start.
    ErrorLog.instance.record(ErrorSteps.cleanup, error);
  }
}
