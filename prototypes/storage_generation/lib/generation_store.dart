import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:sqlite3/sqlite3.dart';

import 'key_slots.dart';
import 'catalog_protection.dart';
import 'lock_wait.dart';

part 'upgrade.dart';

enum GenerationProblem {
  busy,
  lockTimeout,
  lockCancelled,
  operationConflict,
  recoveryRequired,
  alreadyInitialized,
}

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

/// Adapter owns payload schema and binding validation; handles must close before return.
abstract interface class GenerationPayload {
  int get maxBytes;
  String canonicalize(String input);
  Future<void> create(
    File file,
    StorageKey key,
    GenerationReceipt receipt,
    String input,
    void Function(String)? checkpoint,
  );
  Future<String> inspect(File file, StorageKey key, GenerationReceipt receipt);
}

/// Mechanism probe: defaults to closed immutable SQLCipher text fixtures.
/// Atomically publishes pairs. Legacy fixtures use plaintext catalog schema 1;
/// explicit CatalogProtection uses SQLCipher catalog schema 2 with local identity.
final class GenerationStore {
  GenerationStore(
    this.directory,
    this.keys, {
    this.payload,
    this.catalogProtection,
    this.upgradeAware = false,
    this.lockTimeout = const Duration(seconds: 10),
  }) {
    if (upgradeAware && catalogProtection == null)
      throw ArgumentError('Upgrade records require protected catalog storage.');
    if (lockTimeout.isNegative)
      throw ArgumentError.value(lockTimeout, 'lockTimeout');
  }
  final Directory directory;
  final KeySlots keys;
  final GenerationPayload? payload;
  final CatalogProtection? catalogProtection;
  final bool upgradeAware;
  final Duration lockTimeout;
  static final _busy = <String>{};

  File _file(String name) => File('${directory.path}/$name');
  File databaseFile(PublicId generation) => _file('gen-${generation.value}.db');
  static String _fingerprint(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  Future<GenerationReceipt> install(
    String fixture,
    OperationId operation, {
    void Function(String)? checkpoint,
    LockWaitCancellation? cancellation,
    bool onlyIfEmpty = false,
  }) async {
    if (utf8.encode(fixture).length > (payload?.maxBytes ?? 4096))
      throw ArgumentError('Fixture too large');
    fixture = payload?.canonicalize(fixture) ?? fixture;
    if (utf8.encode(fixture).length > (payload?.maxBytes ?? 4096))
      throw ArgumentError('Canonical payload too large');
    return _locked(
      (catalog) async {
        await _recover(catalog);
        if (catalog.userVersion == 3 &&
            catalog.select(
              'SELECT operation FROM upgrade_intents WHERE operation=?',
              [operation.toString()],
            ).isNotEmpty) {
          throw const GenerationUnavailable(
            GenerationProblem.operationConflict,
          );
        }
        final fingerprint = _fingerprint(fixture);
        final earlier = catalog.select(
          'SELECT * FROM attempts WHERE operation=?',
          [operation.toString()],
        );
        if (earlier.any((r) => r['fingerprint'] != fingerprint)) {
          throw const GenerationUnavailable(
            GenerationProblem.operationConflict,
          );
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
        if (onlyIfEmpty && previous != null) {
          throw const GenerationUnavailable(
            GenerationProblem.alreadyInitialized,
          );
        }
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
        return _publish(catalog, receipt, previous, fixture, checkpoint);
      },
      checkpoint: checkpoint,
      cancellation: cancellation,
    );
  }

  /// Both restore and upgrade use the same staging and publication commit point.
  Future<GenerationReceipt> _publish(
    Database catalog,
    GenerationReceipt receipt,
    GenerationReceipt? previous,
    String fixture,
    void Function(String)? checkpoint,
  ) async {
    await keys.create(receipt.slot);
    checkpoint?.call('keySaved');
    await _createDatabase(receipt, fixture, checkpoint);
    checkpoint?.call('staged');
    final staged = await _inspect(
      receipt,
    ); // Reads the persisted key again and reopens the file.
    if (_fingerprint(staged.value) != receipt.fingerprint)
      throw StateError('Staged payload mismatch');
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
  }

  /// The trusted payload adapter must durably save and verify its safety backup
  /// in prepare, while this lease is held. No new catalog DDL precedes prepare.
  Future<UpgradeReceipt> upgrade(
    UpgradeRequest request,
    Future<PreparedUpgrade> Function(InstalledFixture source) prepare, {
    void Function(String)? checkpoint,
    LockWaitCancellation? cancellation,
  }) {
    if (!upgradeAware) throw StateError('Upgrade support is not enabled.');
    return _locked(
      (catalog) async {
        await _recover(catalog);
        final recorded = _findUpgrade(catalog, request);
        if (recorded != null) {
          await _inspect(recorded.target);
          return recorded; // Never reactivate an older published generation.
        }
        final previous = _active(catalog);
        if (previous == null || previous.generation != request.sourceGeneration)
          throw const GenerationUnavailable(
            GenerationProblem.operationConflict,
          );
        final source = await _inspect(previous);
        if (_fingerprint(source.value) != request.sourceDigest)
          throw const GenerationUnavailable(
            GenerationProblem.operationConflict,
          );
        final prepared = await prepare(source);
        if (utf8.encode(prepared.value).length > (payload?.maxBytes ?? 4096))
          throw StateError('Upgrade payload too large');
        final value = payload?.canonicalize(prepared.value) ?? prepared.value;
        if (utf8.encode(value).length > (payload?.maxBytes ?? 4096))
          throw StateError('Canonical upgrade payload too large');
        final fingerprint = _fingerprint(value);
        if (catalog.userVersion == 3 &&
            catalog
                .select(
                  '''SELECT a.fingerprint,u.backup_digest FROM attempts a
              JOIN upgrades u ON u.generation=a.generation WHERE a.operation=?''',
                  [request.operation.toString()],
                )
                .any(
                  (row) =>
                      row['fingerprint'] != fingerprint ||
                      row['backup_digest'] != prepared.backupDigest,
                ))
          throw const GenerationUnavailable(
            GenerationProblem.operationConflict,
          );
        checkpoint?.call('upgradePrepared');
        final receipt = GenerationReceipt(
          PublicId.generate(),
          PublicId.generate(),
          request.operation,
          fingerprint,
        );
        _reserveUpgrade(
          catalog,
          request,
          prepared.backupDigest,
          receipt,
          checkpoint,
        );
        checkpoint?.call('reserved');
        await _publish(catalog, receipt, previous, value, checkpoint);
        return UpgradeReceipt(request, receipt, prepared.backupDigest);
      },
      checkpoint: checkpoint,
      cancellation: cancellation,
      requireExistingCatalog: true,
    );
  }

  /// Preflight callers can refuse missing catalogs instead of initializing one.
  Future<InstalledFixture?> current({
    LockWaitCancellation? cancellation,
    bool requireExistingCatalog = false,
  }) => _locked(
    (catalog) async {
      await _recover(catalog);
      final active = _active(catalog);
      return active == null ? null : _inspect(active);
    },
    cancellation: cancellation,
    requireExistingCatalog: requireExistingCatalog,
  );

  /// Internal adapter scope, not an application connection API. Callback must
  /// close all DB handles before returning and must never retain them.
  Future<T> withCurrent<T>(
    Future<T> Function(File, StorageKey, GenerationReceipt) work, {
    LockWaitCancellation? cancellation,
  }) => _locked((catalog) async {
    await _recover(catalog);
    final active = _active(catalog);
    if (active == null) throw StateError('No active generation');
    return work(
      databaseFile(active.generation),
      await keys.read(active.slot),
      active,
    );
  }, cancellation: cancellation);

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
    if (payload != null) {
      await payload!.create(file, key, receipt, value, checkpoint);
      return;
    }
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
    if (payload != null) {
      return InstalledFixture(
        receipt,
        await payload!.inspect(file, key, receipt),
      );
    }
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

  Future<Database> _catalog(
    void Function(String)? checkpoint, {
    bool allowInitialization = true,
  }) async {
    final file = _file('catalog.db');
    final stage = _file('catalog.init.db');
    await _regular(file, allowAbsent: true);
    await _regular(stage, allowAbsent: true);
    final fresh = !await file.exists();
    if (fresh && !allowInitialization)
      throw StateError('Upgrade requires an existing published catalog.');
    final staged = await stage.exists();
    if (!fresh && staged)
      throw StateError('Conflicting catalog initialization');
    if (fresh) {
      final allowed = {
        _file('lifecycle.lock').uri,
        if (staged) stage.uri,
        if (staged) _file('catalog.init.db-journal').uri,
      };
      final entries = await directory.list(followLinks: false).toList();
      if (entries.any((entry) => !allowed.contains(entry.uri))) {
        throw StateError('Catalog missing with retained artifacts');
      }
    }
    for (final suffix in ['-journal', '-wal', '-shm']) {
      await _regular(_file('catalog.db$suffix'), allowAbsent: true);
      final sidecar = _file('catalog.init.db$suffix');
      await _regular(sidecar, allowAbsent: true);
      if (await sidecar.exists() &&
          (!fresh || !staged || suffix != '-journal')) {
        throw StateError('Unexpected initialization sidecar');
      }
    }
    final protection = catalogProtection;
    // An unfinished stage is still an existing encrypted file: never replace its key.
    final key = await protection?.loadKey(!fresh || staged);
    if (protection != null) checkpoint?.call('catalogKeyReady');
    if (fresh) {
      final candidate = _openCatalog(stage, key);
      try {
        checkpoint?.call('catalogOpened');
        // Only this never-published staging path may resume an empty transaction.
        // Existing catalog.db, unknown schemas and nonempty stages never reset.
        if (candidate.userVersion == 0 &&
            candidate.select('SELECT name FROM sqlite_master').isEmpty) {
          _initializeCatalog(candidate, checkpoint);
        }
        _validateCatalog(candidate);
        _requireEmptyCatalog(candidate);
      } finally {
        candidate.close();
      }
      checkpoint?.call('catalogStaged');
      await _noInitializationSidecars();
      final reopened = _openCatalog(stage, key);
      try {
        _validateCatalog(reopened);
        _requireEmptyCatalog(reopened);
      } finally {
        reopened.close();
      }
      await _noInitializationSidecars();
      checkpoint?.call('catalogValidated');
      await _regular(file, allowAbsent: true);
      if (await file.exists())
        throw StateError('Catalog appeared during initialization');
      checkpoint?.call('catalogPublishing');
      await stage.rename(file.path);
      checkpoint?.call('catalogPublished');
    }
    final db = _openCatalog(file, key);
    try {
      _validateCatalog(db);
      if (fresh) checkpoint?.call('catalogReady');
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  Database _openCatalog(File file, StorageKey? key) {
    final db = sqlite3.open(file.path);
    try {
      if (key != null) configureEncryption(db, key);
      db.execute('PRAGMA foreign_keys=ON');
      db.execute('PRAGMA synchronous=FULL');
      db.execute('PRAGMA busy_timeout=10000');
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  Future<void> _noInitializationSidecars() async {
    for (final suffix in ['-journal', '-wal', '-shm']) {
      if (await FileSystemEntity.type(
            _file('catalog.init.db$suffix').path,
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw StateError('Initialization sidecar remains');
      }
    }
  }

  void _requireEmptyCatalog(Database db) {
    final active = db.select('SELECT * FROM active');
    if (db.select('SELECT generation FROM attempts').isNotEmpty ||
        active.length != 1 ||
        active.single['singleton'] != 1 ||
        active.single['generation'] != null) {
      throw StateError('Initialization stage contains published state');
    }
  }

  void _initializeCatalog(Database db, void Function(String)? checkpoint) {
    final protection = catalogProtection;
    try {
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
      if (protection != null) {
        db.execute(
          'CREATE TABLE catalog_identity (singleton INTEGER PRIMARY KEY CHECK(singleton=1), identity TEXT NOT NULL) STRICT',
        );
        db.execute('INSERT INTO catalog_identity VALUES(1,?)', [
          protection.identity.value,
        ]);
      }
      if (upgradeAware) _createUpgradeTables(db);
      db.execute(
        'PRAGMA user_version=${upgradeAware ? 3 : (protection == null ? 1 : 2)}',
      );
      checkpoint?.call('catalogWriting');
      db.execute('COMMIT');
    } catch (_) {
      if (!db.autocommit) db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _validateCatalog(Database db) {
    final protection = catalogProtection;
    if (!(db.userVersion == (protection == null ? 1 : 2) ||
            (upgradeAware && db.userVersion == 3)) ||
        (protection != null &&
            db.select('PRAGMA cipher_integrity_check').isNotEmpty) ||
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
      if (protection != null) 'catalog_identity': ['singleton', 'identity'],
      if (db.userVersion == 3) ..._upgradeColumns,
    });
    if (protection != null) {
      final identity = db.select('SELECT * FROM catalog_identity');
      if (identity.length != 1 ||
          identity.single['singleton'] != 1 ||
          identity.single['identity'] != protection.identity.value) {
        throw StateError('Catalog identity mismatch');
      }
    }
    if (db.userVersion == 3) _validateUpgrades(db);
  }

  Future<T> _locked<T>(
    Future<T> Function(Database) work, {
    void Function(String)? checkpoint,
    LockWaitCancellation? cancellation,
    bool requireExistingCatalog = false,
  }) async {
    String? identity;
    RandomAccessFile? lock;
    Database? catalog;
    var acquired = false;
    try {
      if (cancellation?.isCancelled ?? false) throw LockWaitAborted();
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
      await acquireLifecycleLock(
        lock,
        timeout: lockTimeout,
        cancellation: cancellation,
      );
      acquired = true;
      catalog = await _catalog(
        checkpoint,
        allowInitialization: !requireExistingCatalog,
      );
      return await work(catalog);
    } on LockWaitExpired {
      throw const GenerationUnavailable(GenerationProblem.lockTimeout);
    } on LockWaitAborted {
      throw const GenerationUnavailable(GenerationProblem.lockCancelled);
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
