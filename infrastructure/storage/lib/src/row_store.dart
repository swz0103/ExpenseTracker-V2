import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// Why a store could not be opened. Never carries key material.
enum StorageProblem {
  /// The SQLite library is not SQLCipher; the file would be plaintext.
  notEncrypted,

  /// The key does not open this file.
  wrongKey,

  /// The file was written by a newer build than this one.
  newerSchema,

  /// Another connection, isolate or process already has the file open;
  /// only one may own a ledger at a time.
  inUse,
}

final class StorageUnavailable implements Exception {
  const StorageUnavailable(this.problem);

  final StorageProblem problem;

  @override
  bool operator ==(Object other) =>
      other is StorageUnavailable && other.problem == problem;

  @override
  int get hashCode => problem.hashCode;

  @override
  String toString() => 'StorageUnavailable(${problem.name})';
}

/// A 256-bit database key. Its bytes never appear in [toString].
final class StorageKey {
  StorageKey(List<int> bytes) : _bytes = Uint8List.fromList(bytes) {
    if (_bytes.length != 32) {
      throw ArgumentError('Storage key must contain 32 bytes.');
    }
  }

  factory StorageKey.random() {
    final random = Random.secure();
    return StorageKey(List.generate(32, (_) => random.nextInt(256)));
  }

  factory StorageKey.fromHex(String hex) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) {
      throw ArgumentError('Storage key must be 64 lowercase hex digits.');
    }
    return StorageKey([
      for (var i = 0; i < 64; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  final Uint8List _bytes;

  String get hex =>
      _bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  @override
  String toString() => 'StorageKey(redacted)';
}

/// One kept record: its [shelf] (such as `entry`), its [id] there and its
/// [body], the record as the app writes it. [seq] is the order it was
/// first kept in; changing a record keeps its place.
final class StoredRow {
  const StoredRow(this.seq, this.shelf, this.id, this.body);

  final int seq;
  final String shelf;
  final String id;
  final String body;
}

/// The changes of one write, applied together.
final class RowWriter {
  RowWriter._(this._db);

  final Database _db;
  bool _open = true;

  /// Keeps [body] as the record [id] on [shelf], in place of any before.
  void put(String shelf, String id, String body) {
    _requireOpen();
    _db.execute(
      'INSERT INTO rows (shelf, id, body) VALUES (?, ?, ?) '
      'ON CONFLICT (shelf, id) DO UPDATE SET body = excluded.body',
      [shelf, id, body],
    );
  }

  /// Forgets the record [id] on [shelf]; nothing when there is none.
  void drop(String shelf, String id) {
    _requireOpen();
    _db.execute('DELETE FROM rows WHERE shelf = ? AND id = ?', [shelf, id]);
  }

  void _requireOpen() {
    if (!_open) throw StateError('Write already finished.');
  }
}

/// The ledger's one encrypted SQLite file: every record the app keeps,
/// each a row of JSON on its shelf.
///
/// SQLite owns crash recovery: an interrupted write is rolled back by
/// SQLite itself on the next open. Each [write] is one transaction.
final class RowStore {
  RowStore._(this._db);

  /// Opens or creates [file].
  factory RowStore.open(File file, StorageKey key) {
    final db = sqlite3.open(file.path);
    try {
      _configure(db, key);
      _create(db);
      return RowStore._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// The layout this build writes.
  static const schema = 1;

  final Database _db;
  bool _closed = false;

  String get journalMode =>
      '${_db.select('PRAGMA journal_mode').single.values.single}';

  /// How many writes this file has had; any change moves it on.
  int get revision {
    _requireOpen();
    final rows = _db.select("SELECT value FROM meta WHERE key = 'revision'");
    return rows.isEmpty ? 0 : rows.single['value'] as int;
  }

  /// How many records are kept.
  int get count {
    _requireOpen();
    return _db.select('SELECT count(*) AS n FROM rows').single['n'] as int;
  }

  /// `ok` when SQLite and SQLCipher find no damage.
  String integrityCheck() {
    _requireOpen();
    final rows = _db.select('PRAGMA integrity_check');
    final cipher = _db.select('PRAGMA cipher_integrity_check');
    final result = rows.map((row) => '${row.values.single}').join('\n');
    return cipher.isEmpty ? result : 'cipher integrity failure';
  }

  /// Every record, in the order first kept; with [shelf], only that
  /// shelf's.
  List<StoredRow> rows({String? shelf}) {
    _requireOpen();
    final found = shelf == null
        ? _db.select('SELECT * FROM rows ORDER BY seq')
        : _db.select('SELECT * FROM rows WHERE shelf = ? ORDER BY seq', [
            shelf,
          ]);
    return [
      for (final row in found)
        StoredRow(
          row['seq'] as int,
          row['shelf'] as String,
          row['id'] as String,
          row['body'] as String,
        ),
    ];
  }

  /// Applies [changes] in one transaction: all of them, or none when it
  /// throws.
  void write(void Function(RowWriter writer) changes) {
    _requireOpen();
    final writer = RowWriter._(_db);
    _db.execute('BEGIN IMMEDIATE');
    try {
      changes(writer);
      _db.execute("UPDATE meta SET value = value + 1 WHERE key = 'revision'");
      _db.execute('COMMIT');
    } catch (_) {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    } finally {
      writer._open = false;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _db.close();
  }

  void _requireOpen() {
    if (_closed) throw StateError('Store is closed.');
  }

  static void _create(Database db) {
    final version = db.userVersion;
    if (version > schema) {
      throw const StorageUnavailable(StorageProblem.newerSchema);
    }
    if (version == schema) return;
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute('''
        CREATE TABLE rows (
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          shelf TEXT NOT NULL,
          id TEXT NOT NULL,
          body TEXT NOT NULL,
          UNIQUE (shelf, id)
        ) STRICT
      ''');
      db.execute('''
        CREATE TABLE meta (
          key TEXT PRIMARY KEY,
          value INTEGER NOT NULL
        ) STRICT, WITHOUT ROWID
      ''');
      db.execute("INSERT INTO meta VALUES ('revision', 0)");
      db.userVersion = schema;
      db.execute('COMMIT');
    } catch (_) {
      if (!db.autocommit) db.execute('ROLLBACK');
      rethrow;
    }
  }

  static void _configure(Database db, StorageKey key) {
    // A plain SQLite build reports no cipher_version and would silently
    // write plaintext, so this is a runtime check, not an assert.
    final version = db.select('PRAGMA cipher_version');
    if (version.isEmpty || '${version.single.values.single}'.isEmpty) {
      throw const StorageUnavailable(StorageProblem.notEncrypted);
    }
    try {
      // hex is exactly 64 hex digits; no user text reaches this statement.
      db.execute('PRAGMA key = "x\'${key.hex}\'"');
      db.select('SELECT count(*) FROM sqlite_master');
    } on SqliteException catch (error) {
      // Never rethrow: the original error may quote the key statement.
      if (error.resultCode == _busy) {
        throw const StorageUnavailable(StorageProblem.inUse);
      }
      throw const StorageUnavailable(StorageProblem.wrongKey);
    } catch (_) {
      throw const StorageUnavailable(StorageProblem.wrongKey);
    }
    db.select('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = FULL');
    db.execute('PRAGMA temp_store = MEMORY');
    // Hold the file for as long as this connection is open, so a second
    // isolate or process cannot write past this one.
    try {
      db.execute('PRAGMA locking_mode = EXCLUSIVE');
      db.execute('BEGIN EXCLUSIVE');
      db.execute('COMMIT');
    } on SqliteException catch (error) {
      if (error.resultCode == _busy) {
        throw const StorageUnavailable(StorageProblem.inUse);
      }
      rethrow;
    }
  }

  /// SQLITE_BUSY.
  static const _busy = 5;
}
