import 'dart:async';
import 'dart:ffi' show Pointer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'journal_store.dart';
import 'layout.dart';

/// Why a store could not be opened. Never carries key material.
enum StorageProblem {
  /// The SQLite library is not SQLCipher; the file would be plaintext.
  notEncrypted,

  /// The key does not open this file.
  wrongKey,

  /// The file was written by a newer build than this one.
  newerSchema,

  /// The file is a ledger of the event-journal format, from before
  /// records were kept as rows; this build cannot read it.
  oldFormat,

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

/// One change of a write done off the caller's isolate
/// ([EncryptedDatabase.writeApart]): a record put in place, or dropped.
/// Plain text only, so it can be sent to another isolate.
final class RowChange {
  /// Keeps [body] as the record [id] on [shelf], in place of any before.
  const RowChange.put(this.shelf, this.id, String this.body);

  /// Forgets the record [id] on [shelf]; nothing when there is none.
  const RowChange.drop(this.shelf, this.id) : body = null;

  final String shelf;
  final String id;

  /// The record kept; null when it is dropped.
  final String? body;
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

  /// Keeps [value] under [key] beside the records, such as the version
  /// the app last brought the book up to ([EncryptedDatabase.meta]).
  void setMeta(String key, int value) {
    _requireOpen();
    if (key == EncryptedDatabase._revision) {
      throw ArgumentError.value(key, 'key', 'kept by the store itself');
    }
    _db.execute(
      'INSERT INTO meta (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
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
final class EncryptedDatabase {
  EncryptedDatabase._(this._db);

  /// Opens or creates [file].
  factory EncryptedDatabase.open(File file, StorageKey key) {
    assert(_layout.length == schema, 'schema is the number of layout steps');
    final db = sqlite3.open(file.path);
    try {
      _configure(db, key);
      _create(db);
      return EncryptedDatabase._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// The layout this build writes: the tables, not what their rows hold.
  /// It is the number of steps in [_layout].
  static const schema = 2;

  /// The steps that bring a file's layout up, one version at a time:
  /// `_layout[n]` takes a file at version n to n + 1. A file is brought
  /// up by every step it lacks, all in one transaction, as it opens; a
  /// new file is at version 0. A change of layout adds a step here and
  /// raises [schema].
  static const List<void Function(Database db)> _layout = [
    _createTables,
    createJournalTables,
  ];

  /// The [meta] key the store keeps its [revision] under.
  static const _revision = 'revision';

  final Database _db;
  bool _closed = false;

  /// The journal of postings kept beside the records, in this file and
  /// derived from them ([createJournalTables]). Used as the records are:
  /// never while a write runs apart, never once closed.
  late final SqlPostingStore journal = SqlPostingStore(_db, _requireOpen);

  /// A write running on another isolate ([writeApart]); done when it is.
  Completer<void>? _apart;

  /// The [revision] as it stood when that write began.
  int _revisionBefore = 0;

  /// Closed while a write ran apart: closed once it is done.
  bool _closeAfter = false;

  /// Whether a write is running on another isolate ([writeApart]).
  bool get writingApart => _apart != null;

  /// Done once no write runs on another isolate.
  Future<void> get idle => _apart?.future ?? Future<void>.value();

  String get journalMode =>
      '${_db.select('PRAGMA journal_mode').single.values.single}';

  /// How many changes this file has had; a write that does not count
  /// (see [write]) leaves it.
  int get revision {
    if (_apart != null && !_closed) return _revisionBefore;
    _requireOpen();
    final rows = _db.select("SELECT value FROM meta WHERE key = 'revision'");
    return rows.isEmpty ? 0 : rows.single['value'] as int;
  }

  /// The number kept under [key] beside the records, or null when none
  /// is ([RowWriter.setMeta]).
  int? meta(String key) {
    _requireOpen();
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.single['value'] as int;
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
    return [for (final row in found) _stored(row)];
  }

  /// The record [id] on [shelf], or null when there is none.
  StoredRow? row(String shelf, String id) {
    _requireOpen();
    final found = _db.select('SELECT * FROM rows WHERE shelf = ? AND id = ?', [
      shelf,
      id,
    ]);
    return found.isEmpty ? null : _stored(found.single);
  }

  static StoredRow _stored(Row row) => StoredRow(
    row['seq'] as int,
    row['shelf'] as String,
    row['id'] as String,
    row['body'] as String,
  );

  /// At most [limit] records kept after the one numbered [after], in the
  /// order first kept: a large book read a page at a time, so the app can
  /// draw between pages rather than wait for the whole book at once. Pass
  /// the last page's last [StoredRow.seq] for the next.
  List<StoredRow> rowsAfter(int after, {int limit = 5000}) {
    _requireOpen();
    return [
      for (final row in _db.select(
        'SELECT * FROM rows WHERE seq > ? ORDER BY seq LIMIT ?',
        [after, limit],
      ))
        _stored(row),
    ];
  }

  /// Applies [changes] in one transaction: all of them, or none when it
  /// throws. A write that [counts] moves [revision] on; one that does not,
  /// such as fetched prices, leaves it, so a backup is not taken for it.
  void write(void Function(RowWriter writer) changes, {bool counts = true}) {
    _requireOpen();
    _transaction(_db, changes, counts: counts);
  }

  static void _transaction(
    Database db,
    void Function(RowWriter writer) changes, {
    required bool counts,
  }) {
    final writer = RowWriter._(db);
    db.execute('BEGIN IMMEDIATE');
    try {
      changes(writer);
      if (counts) {
        db.execute("UPDATE meta SET value = value + 1 WHERE key = 'revision'");
      }
      db.execute('COMMIT');
    } catch (_) {
      if (!db.autocommit) db.execute('ROLLBACK');
      rethrow;
    } finally {
      writer._open = false;
    }
  }

  /// Whether the file can still be read and written: not [close]d, nor
  /// to be closed once a write apart is done.
  bool get isOpen => !_closed && !_closeAfter;

  /// Applies [changes] in one transaction, as [write] does, on a worker
  /// isolate through this same connection, so a large batch (a merchant
  /// renamed on every entry, an import, a restore) never holds the
  /// caller's isolate, and with it the screen, still. Until it is done
  /// ([idle]) nothing else may use the store: [revision] answers the
  /// revision as it stood before, any other read or write throws a
  /// [StateError], and [close] waits for it. All of [changes], or none
  /// when it throws.
  Future<void> writeApart(List<RowChange> changes, {bool counts = true}) async {
    _requireOpen();
    _revisionBefore = revision;
    final done = _apart = Completer<void>();
    try {
      await _applyApart(_db.handle.address, changes, counts);
    } finally {
      _apart = null;
      done.complete();
      if (_closeAfter) close();
    }
  }

  /// Kept apart from the instance, so the closure sent to the worker
  /// carries the changes and the connection's address, never `this`.
  static Future<void> _applyApart(
    int address,
    List<RowChange> changes,
    bool counts,
  ) => Isolate.run(() {
    // A view of the connection this isolate opened: not closed here.
    final db = sqlite3.fromPointer(
      Pointer.fromAddress(address),
      borrowed: true,
    );
    try {
      _transaction(db, (w) {
        for (final change in changes) {
          final body = change.body;
          if (body == null) {
            w.drop(change.shelf, change.id);
          } else {
            w.put(change.shelf, change.id, body);
          }
        }
      }, counts: counts);
    } finally {
      db.close();
    }
  });

  /// Closes the store; while a write runs apart, once it is done.
  void close() {
    if (_closed) return;
    if (_apart != null) {
      _closeAfter = true;
      return;
    }
    _closed = true;
    journal.close();
    _db.close();
  }

  void _requireOpen() {
    if (_closed) throw StateError('Store is closed.');
    if (_apart != null) {
      throw StateError('Store is busy with a write apart.');
    }
  }

  static void _create(Database db) {
    final journal = db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'events'",
    );
    if (journal.isNotEmpty) {
      throw const StorageUnavailable(StorageProblem.oldFormat);
    }
    bringUpLayout(db, _layout);
  }

  /// Version 0 to 1: the records' table and the store's own.
  static void _createTables(Database db) {
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
    db.execute("INSERT INTO meta VALUES ('$_revision', 0)");
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
    // FULL: a save has reached the disk once it returns, so not even a
    // power cut in the moment after it loses it (NORMAL could lose that
    // last save). Measured on the emulator (bench_test.dart): a save takes
    // 0.45-1.1 ms, the slowest twentieth 1.0-1.3 ms (NORMAL: 0.15 and
    // about 1), far under a 16.7 ms frame.
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
