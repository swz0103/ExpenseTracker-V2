import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:sqlite3/sqlite3.dart';

import 'key_slots.dart';

enum GenerationProblem { busy, operationConflict, recoveryRequired }

final class GenerationUnavailable implements Exception {
  const GenerationUnavailable(this.problem);
  final GenerationProblem problem;
  @override
  String toString() => 'GenerationUnavailable(${problem.name})';
}

final class GenerationReceipt {
  GenerationReceipt(
    this.generation,
    this.slot,
    this.operation,
    this.fingerprint,
  );
  final PublicId generation;
  final PublicId slot;
  final OperationId operation;
  final String fingerprint;
  factory GenerationReceipt.fromRow(Row row) {
    final fingerprint = row['fingerprint'] as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      throw StateError('Invalid fingerprint');
    }
    return GenerationReceipt(
      PublicId.parse(row['generation'] as String),
      PublicId.parse(row['slot'] as String),
      OperationId.parse(row['operation'] as String),
      fingerprint,
    );
  }
}

final class InstalledFixture {
  InstalledFixture(this.receipt, this.value);
  final GenerationReceipt receipt;
  final String value;
}

/// Mechanism probe only: closed immutable SQLCipher fixtures, no Ledger schema.
/// A non-secret SQLite catalog atomically publishes the generation/key-slot pair.
final class GenerationStore {
  GenerationStore(this.directory, this.keys);
  final Directory directory;
  final KeySlots keys;
  static final _busy = <String>{};

  File _file(String name) => File('${directory.path}/$name');
  File databaseFile(PublicId generation) => _file('gen-${generation.value}.db');
  static String _fingerprint(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  Future<GenerationReceipt> install(
    String fixture,
    OperationId operation, {
    void Function(String)? checkpoint,
  }) async {
    if (utf8.encode(fixture).length > 4096)
      throw ArgumentError('Fixture too large');
    return _locked((catalog) async {
      await _recover(catalog);
      final fingerprint = _fingerprint(fixture);
      final earlier = catalog.select(
        'SELECT * FROM attempts WHERE operation=?',
        [operation.toString()],
      );
      if (earlier.any((r) => r['fingerprint'] != fingerprint)) {
        throw const GenerationUnavailable(GenerationProblem.operationConflict);
      }
      final committed = earlier
          .where((r) => r['status'] == 'committed')
          .toList();
      if (committed.isNotEmpty) {
        final receipt = GenerationReceipt.fromRow(committed.single);
        await _inspect(receipt);
        return receipt; // Does not reactivate an older committed generation.
      }
      final previous = _active(catalog);
      final receipt = GenerationReceipt(
        PublicId.generate(),
        PublicId.generate(),
        operation,
        fingerprint,
      );
      catalog.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?)', [
        receipt.generation.value,
        receipt.slot.value,
        operation.toString(),
        fingerprint,
        'pending',
        previous?.generation.value,
      ]);
      checkpoint?.call('reserved');
      await keys.create(receipt.slot);
      checkpoint?.call('keySaved');
      await _createDatabase(receipt, fixture, checkpoint);
      checkpoint?.call('staged');
      await _inspect(
        receipt,
      ); // Reads the persisted key again and reopens the file.
      checkpoint?.call('validated');
      catalog.execute('BEGIN IMMEDIATE');
      try {
        if (_active(catalog)?.generation != previous?.generation)
          throw StateError('Active reference changed');
        catalog.execute(
          "UPDATE attempts SET status='committed' WHERE generation=? AND status='pending'",
          [receipt.generation.value],
        );
        catalog.execute('UPDATE active SET generation=? WHERE singleton=1', [
          receipt.generation.value,
        ]);
        checkpoint?.call('publishing');
        catalog.execute('COMMIT'); // The only publication commit point.
      } catch (_) {
        if (!catalog.autocommit) catalog.execute('ROLLBACK');
        rethrow;
      }
      checkpoint?.call('published');
      await _inspect(_active(catalog)!);
      return receipt;
    });
  }

  Future<InstalledFixture?> current() => _locked((catalog) async {
    await _recover(catalog);
    final active = _active(catalog);
    return active == null ? null : _inspect(active);
  });

  GenerationReceipt? _active(Database catalog) {
    final refs = catalog.select(
      'SELECT generation FROM active WHERE singleton=1',
    );
    if (refs.length != 1) throw StateError('Invalid active reference');
    final id = refs.single['generation'];
    if (id == null) return null;
    final rows = catalog.select(
      "SELECT * FROM attempts WHERE generation=? AND status='committed'",
      [id],
    );
    if (rows.length != 1) throw StateError('Invalid active generation');
    return GenerationReceipt.fromRow(rows.single);
  }

  Future<void> _recover(Database catalog) async {
    final active = _active(catalog);
    if (active != null) await _inspect(active);
    final pending = catalog.select(
      "SELECT * FROM attempts WHERE status='pending'",
    );
    if (pending.length > 1) throw StateError('Conflicting pending generations');
    for (final row in pending) {
      GenerationReceipt.fromRow(row); // Validate all path-bearing identities.
      if (row['previous'] != active?.generation.value)
        throw StateError('Conflicting intent');
      // Only uncommitted attempts are retired; files and key slots remain retained.
      catalog.execute(
        "UPDATE attempts SET status='aborted' WHERE generation=?",
        [row['generation']],
      );
    }
  }

  Future<void> _createDatabase(
    GenerationReceipt receipt,
    String value,
    void Function(String)? checkpoint,
  ) async {
    final file = databaseFile(receipt.generation);
    await _regular(file, allowAbsent: true);
    if (await file.exists()) throw StateError('Generation already exists');
    final key = await keys.read(receipt.slot);
    final db = sqlite3.open(file.path);
    try {
      configureEncryption(db, key);
      db.execute('BEGIN IMMEDIATE');
      db.execute(
        'CREATE TABLE identity (singleton INTEGER PRIMARY KEY CHECK(singleton=1), generation TEXT NOT NULL, slot TEXT NOT NULL, operation TEXT NOT NULL, fingerprint TEXT NOT NULL) STRICT',
      );
      db.execute(
        'CREATE TABLE fixture (singleton INTEGER PRIMARY KEY CHECK(singleton=1), value TEXT NOT NULL) STRICT',
      );
      db.execute('INSERT INTO identity VALUES(1,?,?,?,?)', [
        receipt.generation.value,
        receipt.slot.value,
        receipt.operation.toString(),
        receipt.fingerprint,
      ]);
      checkpoint?.call('databaseWriting');
      db.execute('INSERT INTO fixture VALUES(1,?)', [value]);
      db.execute('PRAGMA user_version=1');
      db.execute('COMMIT');
    } finally {
      db.close();
    }
  }

  Future<InstalledFixture> _inspect(GenerationReceipt receipt) async {
    final file = databaseFile(receipt.generation);
    await _regular(file);
    for (final suffix in ['-journal', '-wal', '-shm']) {
      if (await FileSystemEntity.type(
            '${file.path}$suffix',
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw StateError('Unexpected generation sidecar');
      }
    }
    final key = await keys.read(receipt.slot);
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      configureEncryption(db, key);
      _checkSchema(db, {
        'identity': [
          'singleton',
          'generation',
          'slot',
          'operation',
          'fingerprint',
        ],
        'fixture': ['singleton', 'value'],
      });
      if (db.userVersion != 1 ||
          db.select('PRAGMA integrity_check').single.values.single != 'ok' ||
          db.select('PRAGMA cipher_integrity_check').isNotEmpty)
        throw StateError('Invalid generation');
      final rows = db.select('SELECT * FROM identity');
      if (rows.length != 1 ||
          rows.single['singleton'] != 1 ||
          rows.single['generation'] != receipt.generation.value ||
          rows.single['slot'] != receipt.slot.value ||
          rows.single['operation'] != receipt.operation.toString() ||
          rows.single['fingerprint'] != receipt.fingerprint) {
        throw StateError('Generation identity mismatch');
      }
      final values = db.select(
        'SELECT value FROM fixture WHERE singleton=1 AND length(CAST(value AS BLOB))<=4096',
      );
      if (values.length != 1 ||
          _fingerprint(values.single['value'] as String) !=
              receipt.fingerprint) {
        throw StateError('Generation content mismatch');
      }
      return InstalledFixture(receipt, values.single['value'] as String);
    } finally {
      db.close();
    }
  }

  Future<void> _regular(File file, {bool allowAbsent = false}) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        !(allowAbsent && type == FileSystemEntityType.notFound)) {
      throw StateError('Unexpected file type');
    }
  }

  Future<Database> _catalog() async {
    final file = _file('catalog.db');
    await _regular(file, allowAbsent: true);
    final fresh = !await file.exists();
    if (fresh) {
      final entries = await directory.list(followLinks: false).toList();
      if (entries.any((entry) => entry.uri != _file('lifecycle.lock').uri)) {
        throw StateError('Catalog missing with retained artifacts');
      }
    }
    for (final suffix in ['-journal', '-wal', '-shm']) {
      await _regular(_file('catalog.db$suffix'), allowAbsent: true);
    }
    // Catalog holds only opaque references and fingerprints, never keys/payloads.
    final db = sqlite3.open(file.path);
    try {
      db.execute('PRAGMA foreign_keys=ON');
      db.execute('PRAGMA synchronous=FULL');
      db.execute('PRAGMA busy_timeout=10000');
      if (fresh) {
        db.execute('BEGIN IMMEDIATE');
        db.execute(
          "CREATE TABLE attempts (generation TEXT PRIMARY KEY, slot TEXT NOT NULL UNIQUE, operation TEXT NOT NULL, fingerprint TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('pending','committed','aborted')), previous TEXT REFERENCES attempts(generation)) STRICT",
        );
        db.execute(
          "CREATE UNIQUE INDEX committed_operation ON attempts(operation) WHERE status='committed'",
        );
        db.execute(
          "CREATE UNIQUE INDEX one_pending ON attempts(status) WHERE status='pending'",
        );
        db.execute(
          'CREATE TABLE active (singleton INTEGER PRIMARY KEY CHECK(singleton=1), generation TEXT REFERENCES attempts(generation)) STRICT',
        );
        db.execute('INSERT INTO active VALUES(1,NULL)');
        db.execute('PRAGMA user_version=1');
        db.execute('COMMIT');
      }
      if (db.userVersion != 1 ||
          db.select('PRAGMA integrity_check').single.values.single != 'ok' ||
          db.select('PRAGMA foreign_key_check').isNotEmpty)
        throw StateError('Invalid catalog');
      _checkSchema(db, {
        'attempts': [
          'generation',
          'slot',
          'operation',
          'fingerprint',
          'status',
          'previous',
        ],
        'active': ['singleton', 'generation'],
      });
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  Future<T> _locked<T>(Future<T> Function(Database) work) async {
    String? identity;
    RandomAccessFile? lock;
    Database? catalog;
    var acquired = false;
    try {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw StateError('Unexpected root');
      }
      await directory.create(recursive: true);
      final root = await directory.resolveSymbolicLinks();
      final candidate = Platform.isWindows ? root.toLowerCase() : root;
      if (!_busy.add(candidate))
        throw const GenerationUnavailable(GenerationProblem.busy);
      identity = candidate;
      final lockFile = _file('lifecycle.lock');
      await _regular(lockFile, allowAbsent: true);
      lock = await lockFile.open(mode: FileMode.append);
      await lock.lock(FileLock.blockingExclusive);
      acquired = true;
      catalog = await _catalog();
      return await work(catalog);
    } on GenerationUnavailable {
      rethrow;
    } catch (_) {
      // Includes ambiguous publication results: retry uses the saved receipt.
      throw const GenerationUnavailable(GenerationProblem.recoveryRequired);
    } finally {
      try {
        catalog?.close();
      } finally {
        try {
          if (acquired) await lock!.unlock();
        } finally {
          try {
            await lock?.close();
          } finally {
            if (identity != null) _busy.remove(identity);
          }
        }
      }
    }
  }

  void _checkSchema(Database db, Map<String, List<String>> expected) {
    if (db
        .select(
          "SELECT name FROM sqlite_master WHERE type IN ('view','trigger')",
        )
        .isNotEmpty) {
      throw StateError('Unsupported schema objects');
    }
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*'",
    );
    if (tables.length != expected.length ||
        tables.any((r) => !expected.containsKey(r['name']))) {
      throw StateError('Unsupported schema');
    }
    for (final entry in expected.entries) {
      final columns = db.select('PRAGMA table_xinfo(${entry.key})');
      if (columns.length != entry.value.length ||
          columns.any((r) => !entry.value.contains(r['name']))) {
        throw StateError('Unsupported schema');
      }
    }
  }
}
