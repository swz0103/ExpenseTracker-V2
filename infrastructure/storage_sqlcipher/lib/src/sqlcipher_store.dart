import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

/// Why a store could not be opened. Never carries key material.
enum StorageProblem {
  /// The SQLite library is not SQLCipher; the file would be plaintext.
  notEncrypted,

  /// The key does not open this file.
  wrongKey,

  /// The file was written by a newer schema than this build understands.
  newerSchema,
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

final class StoredEvent {
  const StoredEvent({
    required this.seq,
    required this.id,
    required this.workspace,
    required this.kind,
    required this.payload,
  });

  final int seq;
  final PublicId id;
  final WorkspaceId workspace;
  final String kind;
  final String payload;
}

final _kindPattern = RegExp(r'^[a-z][a-z0-9.\-]{0,63}$');
const _outboxPage = 'SELECT * FROM outbox ORDER BY seq LIMIT ?';

/// One encrypted SQLite database in WAL mode holding the append-only event
/// journal, the operation journal and the outbox.
///
/// SQLite owns crash recovery: an interrupted transaction is rolled back by
/// SQLite itself on the next open, never treated as tampering.
final class SqlCipherStore implements UnitOfWork<SqlTransaction> {
  SqlCipherStore._(this._db);

  /// Opens or creates [file], applying any pending migrations.
  factory SqlCipherStore.open(File file, StorageKey key) {
    final db = sqlite3.open(file.path);
    try {
      _configure(db, key);
      _migrate(db);
      return SqlCipherStore._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static int get latestSchema => migrations.length;

  final Database _db;
  bool _writing = false;
  bool _closed = false;

  int get schemaVersion => _db.userVersion;

  String get journalMode =>
      '${_db.select('PRAGMA journal_mode').single.values.single}';

  int get eventCount => _count('events');

  int get operationCount => _count('operations');

  /// `ok` when SQLite and SQLCipher find no damage.
  String integrityCheck() {
    _requireOpen();
    final rows = _db.select('PRAGMA integrity_check');
    final cipher = _db.select('PRAGMA cipher_integrity_check');
    final result = rows.map((row) => '${row.values.single}').join('\n');
    return cipher.isEmpty ? result : 'cipher integrity failure';
  }

  List<StoredEvent> events(
    WorkspaceId workspace, {
    int afterSeq = 0,
    int limit = 500,
  }) {
    _requireOpen();
    final rows = _db.select(
      'SELECT * FROM events WHERE workspace=? AND seq>? ORDER BY seq LIMIT ?',
      [workspace.toString(), afterSeq, limit],
    );
    return rows.map(_event).toList();
  }

  /// Committed outbox messages in commit order.
  List<OutboxMessage> pendingOutbox({int limit = 50}) {
    _requireOpen();
    final rows = _db.select(_outboxPage, [limit]);
    return rows.map(_message).toList();
  }

  /// Removes a delivered outbox message.
  void acknowledge(PublicId id) {
    _requireOpen();
    _db.execute('DELETE FROM outbox WHERE id = ?', [id.value]);
  }

  @override
  Future<R> write<R>(
    Future<R> Function(SqlTransaction transaction) body,
  ) async {
    _requireOpen();
    if (_writing) throw StateError('Overlapping write transactions.');
    _writing = true;
    final transaction = SqlTransaction._(_db);
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = await body(transaction);
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    } finally {
      transaction._open = false;
      _writing = false;
    }
  }

  void close() {
    if (_closed) return;
    if (_writing) throw StateError('Cannot close during a write.');
    _closed = true;
    _db.close();
  }

  int _count(String table) {
    _requireOpen();
    return _db.select('SELECT count(*) AS n FROM $table').single['n'] as int;
  }

  void _requireOpen() {
    if (_closed) throw StateError('Store is closed.');
  }

  static StoredEvent _event(Row row) {
    return StoredEvent(
      seq: row['seq'] as int,
      id: PublicId.parse(row['id'] as String),
      workspace: WorkspaceId.parse(row['workspace'] as String),
      kind: row['kind'] as String,
      payload: row['payload'] as String,
    );
  }

  static OutboxMessage _message(Row row) {
    return OutboxMessage(
      id: PublicId.parse(row['id'] as String),
      topic: row['topic'] as String,
      payload: row['payload'] as String,
    );
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
    } catch (_) {
      // Never rethrow: the original error may quote the key statement.
      throw const StorageUnavailable(StorageProblem.wrongKey);
    }
    db.select('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = FULL');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA temp_store = MEMORY');
  }

  static void _migrate(Database db) {
    final current = db.userVersion;
    if (current > migrations.length) {
      throw const StorageUnavailable(StorageProblem.newerSchema);
    }
    for (var version = current; version < migrations.length; version++) {
      db.execute('BEGIN IMMEDIATE');
      try {
        for (final statement in migrations[version]) {
          db.execute(statement);
        }
        db.userVersion = version + 1;
        db.execute('COMMIT');
      } catch (_) {
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      }
    }
  }
}

final class SqlTransaction implements WriteTransaction {
  SqlTransaction._(this._db);

  final Database _db;
  bool _open = true;

  /// Appends an immutable event and returns its sequence number.
  int append({
    required PublicId id,
    required WorkspaceId workspace,
    required String kind,
    required String payload,
  }) {
    _requireOpen();
    if (!_kindPattern.hasMatch(kind)) {
      throw ArgumentError.value(kind, 'kind', 'Invalid event kind.');
    }
    _db.execute(
      'INSERT INTO events (id, workspace, kind, payload) VALUES (?, ?, ?, ?)',
      [id.value, workspace.toString(), kind, payload],
    );
    return _db.lastInsertRowId;
  }

  @override
  Future<RecordedOperation?> findOperation(OperationKey key) async {
    _requireOpen();
    final rows = _db.select(
      'SELECT * FROM operations WHERE workspace = ? AND operation_id = ?',
      [key.workspace.toString(), key.operation.toString()],
    );
    if (rows.isEmpty) return null;
    return RecordedOperation(
      key: key,
      input: rows.single['input'] as String,
      result: rows.single['result'] as String,
    );
  }

  @override
  Future<void> recordOperation(RecordedOperation operation) async {
    _requireOpen();
    _db.execute(
      'INSERT INTO operations VALUES (?, ?, ?, ?)',
      [
        operation.key.workspace.toString(),
        operation.key.operation.toString(),
        operation.input,
        operation.result,
      ],
    );
  }

  @override
  Future<void> enqueue(OutboxMessage message) async {
    _requireOpen();
    _db.execute(
      'INSERT INTO outbox (id, topic, payload) VALUES (?, ?, ?)',
      [message.id.value, message.topic, message.payload],
    );
  }

  void _requireOpen() {
    if (!_open) throw StateError('Transaction already finished.');
  }
}
