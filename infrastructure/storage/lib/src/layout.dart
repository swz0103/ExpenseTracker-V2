import 'package:sqlite3/sqlite3.dart';

import 'encrypted_database.dart';

/// Brings [db] up to the layout [steps] end at, `steps.length`, through
/// each step it lacks: `steps[n]` takes a file at version n (SQLite's
/// `user_version`) to n + 1, and a new file is at version 0. All the
/// steps run in one transaction, so a step that throws leaves the file
/// as it was. A file of a later layout than [steps] reach is refused.
void bringUpLayout(Database db, List<void Function(Database db)> steps) {
  final version = db.userVersion;
  if (version > steps.length) {
    throw const StorageUnavailable(StorageProblem.newerSchema);
  }
  if (version == steps.length) return;
  db.execute('BEGIN IMMEDIATE');
  try {
    for (final step in steps.skip(version)) {
      step(db);
    }
    db.userVersion = steps.length;
    db.execute('COMMIT');
  } catch (_) {
    if (!db.autocommit) db.execute('ROLLBACK');
    rethrow;
  }
}
