import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// The system's "no space left on the device": ENOSPC on Linux and
/// Android.
const _enospc = 28;

/// The same on Windows: ERROR_DISK_FULL.
const _diskFull = 112;

/// SQLite's own (SQLITE_FULL): what a write into the database is refused
/// with when the device has no room left (ENOSPC), or when it would grow
/// past `max_page_count`. Its extended codes share this primary code.
const _sqliteFull = 13;

/// Whether [error] is a write refused for want of room on the device: a
/// failure that goes away once space is freed, not one in the file: a
/// file written ([FileSystemException]) or the database ([SqliteException]
/// SQLITE_FULL, review 30).
bool isNoSpace(Object error) => switch (error) {
  FileSystemException(osError: OSError(errorCode: _enospc || _diskFull)) =>
    true,
  final SqliteException e => e.resultCode == _sqliteFull,
  _ => false,
};
