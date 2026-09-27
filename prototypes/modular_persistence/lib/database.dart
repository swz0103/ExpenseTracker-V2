import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'storage_binding.dart';
import 'category_schema.dart';
import 'allocation_schema.dart';

/// Host integration fixture. Handwritten SQL, no reactive streams.
final class ProbeDatabase extends GeneratedDatabase {
  ProbeDatabase(
    File file, {
    this.migrationCheckpoint,
    this.storageBinding,
    bool categoryAware = false,
    this.categoryReferences = false,
  }) : categoryAware = categoryAware || categoryReferences,
       super(NativeDatabase(file)) {
    _configuration();
  }
  ProbeDatabase.withExecutor(
    QueryExecutor executor, {
    this.migrationCheckpoint,
    this.storageBinding,
    bool categoryAware = false,
    this.categoryReferences = false,
  }) : categoryAware = categoryAware || categoryReferences,
       super(executor) {
    _configuration();
  }
  final bool categoryAware;
  final bool categoryReferences;
  void _configuration() {
    if (categoryAware && storageBinding == null) {
      throw ArgumentError('Categories require an explicitly bound stage.');
    }
  }

  final void Function(String)? migrationCheckpoint;
  final StorageBinding? storageBinding;
  @override
  int get schemaVersion => categoryReferences
      ? 5
      : (categoryAware ? 4 : (storageBinding == null ? 2 : 3));
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(() async {
      for (final sql in _schema) {
        await customStatement(
          categoryReferences && sql.startsWith('CREATE TABLE allocations ')
              ? allocationReferenceSchema
              : sql,
        );
      }
      await _upgradeV2();
      if (storageBinding != null) await _upgradeV3();
      if (categoryAware) {
        for (final sql in categorySchema) {
          await customStatement(sql);
        }
        migrationCheckpoint?.call('categories');
      }
    }),
    onUpgrade: (_, from, to) async {
      if (categoryAware) {
        throw StateError(
          'Categories schemas require a new validated stage, not in-place migration.',
        );
      }
      if (from == 1 && to == 2) {
        await transaction(_upgradeV2);
      } else if ((from == 1 || from == 2) &&
          to == 3 &&
          storageBinding != null) {
        await transaction(() async {
          if (from == 1) await _upgradeV2();
          await _upgradeV3();
        });
      } else {
        throw StateError('No migration from $from to $to.');
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 10000');
      if (storageBinding != null) await verifyStorageBinding();
    },
  );

  Future<void> _upgradeV3() async {
    await customStatement(
      'CREATE TABLE storage_identity (singleton INTEGER PRIMARY KEY CHECK(singleton=1), generation TEXT NOT NULL, slot TEXT NOT NULL, operation TEXT NOT NULL, fingerprint TEXT NOT NULL) STRICT',
    );
    await customStatement(
      'INSERT INTO storage_identity VALUES(1,?,?,?,?)',
      storageBinding!.values,
    );
    migrationCheckpoint?.call('binding');
  }

  Future<void> verifyStorageBinding() async {
    final binding = storageBinding;
    if (binding == null) throw StateError('No storage binding');
    const columns = [
      'singleton',
      'generation',
      'slot',
      'operation',
      'fingerprint',
    ];
    final shape = await customSelect('PRAGMA table_xinfo(storage_identity)')
        .get();
    if (shape.length != columns.length ||
        shape.any((r) => !columns.contains(r.read<String>('name')))) {
      throw StateError('Unknown storage identity schema');
    }
    final rows = await customSelect('SELECT * FROM storage_identity').get();
    if (rows.length != 1 || rows.single.read<int>('singleton') != 1) {
      throw StateError('Invalid storage identity');
    }
    for (var i = 0; i < binding.values.length; i++) {
      if (rows.single.read<String>(columns[i + 1]) != binding.values[i]) {
        throw StateError('Storage identity mismatch');
      }
    }
  }

  Future<void> _upgradeV2() async {
    await customStatement(
      "ALTER TABLE events ADD COLUMN source_context TEXT NOT NULL DEFAULT 'legacy-unspecified'",
    );
    migrationCheckpoint?.call('column');
    await customStatement(
      'CREATE INDEX legs_by_account ON legs(workspace,account_id)',
    );
    migrationCheckpoint?.call('index');
    if ((await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
      throw StateError('Foreign key violations after migration.');
    }
  }
}

const _schema = [
  '''CREATE TABLE accounts (
    workspace TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY (workspace,id)) STRICT''',
  '''CREATE TABLE events (
    workspace TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL,
    business_date TEXT NOT NULL, income INTEGER NOT NULL, expense INTEGER NOT NULL,
    currency TEXT NOT NULL, scale INTEGER NOT NULL,
    PRIMARY KEY (workspace,id)) STRICT''',
  '''CREATE TABLE legs (
    workspace TEXT NOT NULL, event_id TEXT NOT NULL, ordinal INTEGER NOT NULL,
    account_id TEXT NOT NULL, amount INTEGER NOT NULL, currency TEXT NOT NULL,
    scale INTEGER NOT NULL, role TEXT NOT NULL,
    PRIMARY KEY (workspace,event_id,ordinal),
    FOREIGN KEY (workspace,event_id) REFERENCES events(workspace,id),
    FOREIGN KEY (workspace,account_id) REFERENCES accounts(workspace,id)) STRICT''',
  '''CREATE TABLE openings (
    workspace TEXT NOT NULL, account_id TEXT NOT NULL, event_id TEXT NOT NULL,
    PRIMARY KEY (workspace,account_id),
    FOREIGN KEY (workspace,account_id) REFERENCES accounts(workspace,id),
    FOREIGN KEY (workspace,event_id) REFERENCES events(workspace,id)) STRICT''',
  '''CREATE TABLE allocations (
    workspace TEXT NOT NULL, event_id TEXT NOT NULL, category_id TEXT NOT NULL,
    amount INTEGER NOT NULL, PRIMARY KEY(workspace,event_id,category_id),
    FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id)) STRICT''',
  '''CREATE TABLE receipts (
    workspace TEXT NOT NULL, operation_id TEXT NOT NULL, input TEXT NOT NULL,
    result_id TEXT NOT NULL, PRIMARY KEY(workspace,operation_id)) STRICT''',
  '''CREATE TABLE audit (
    workspace TEXT NOT NULL, operation_id TEXT NOT NULL, entity_id TEXT NOT NULL,
    kind TEXT NOT NULL, recorded_at TEXT NOT NULL,
    PRIMARY KEY(workspace,operation_id),
    FOREIGN KEY(workspace,operation_id) REFERENCES receipts(workspace,operation_id)) STRICT''',
];
