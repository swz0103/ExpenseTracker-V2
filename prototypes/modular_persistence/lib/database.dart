import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'storage_binding.dart';
import 'category_schema.dart';
import 'tag_schema.dart';
import 'merchant_schema.dart';
import 'merchant_reference_schema.dart';
import 'tag_reference_schema.dart';
import 'allocation_schema.dart';

/// Host integration fixture. Handwritten SQL, no reactive streams.
final class ProbeDatabase extends GeneratedDatabase {
  ProbeDatabase(
    File file, {
    this.migrationCheckpoint,
    this.storageBinding,
    bool categoryAware = false,
    bool categoryReferences = false,
    bool tagsAware = false,
    bool merchantsAware = false,
    bool transfersAware = false,
    bool fxTransfersAware = false,
    bool refundsAware = false,
    bool reversalsAware = false,
    bool notesAware = false,
    this.correctionsAware = false,
  }) : notesAware = notesAware || correctionsAware,
       reversalsAware = reversalsAware || notesAware || correctionsAware,
       refundsAware =
           refundsAware || reversalsAware || notesAware || correctionsAware,
       fxTransfersAware =
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       transfersAware =
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       merchantsAware =
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       tagsAware =
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       categoryReferences =
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       categoryAware =
           categoryAware ||
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       super(NativeDatabase(file)) {
    _configuration();
  }
  ProbeDatabase.withExecutor(
    QueryExecutor executor, {
    this.migrationCheckpoint,
    this.storageBinding,
    bool categoryAware = false,
    bool categoryReferences = false,
    bool tagsAware = false,
    bool merchantsAware = false,
    bool transfersAware = false,
    bool fxTransfersAware = false,
    bool refundsAware = false,
    bool reversalsAware = false,
    bool notesAware = false,
    this.correctionsAware = false,
  }) : notesAware = notesAware || correctionsAware,
       reversalsAware = reversalsAware || notesAware || correctionsAware,
       refundsAware =
           refundsAware || reversalsAware || notesAware || correctionsAware,
       fxTransfersAware =
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       transfersAware =
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       merchantsAware =
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       tagsAware =
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       categoryReferences =
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       categoryAware =
           categoryAware ||
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       super(executor) {
    _configuration();
  }
  final bool categoryAware;
  final bool categoryReferences;
  final bool tagsAware;
  final bool merchantsAware;
  final bool transfersAware;
  final bool fxTransfersAware;
  final bool refundsAware;
  final bool reversalsAware;
  final bool notesAware;
  final bool correctionsAware;
  void _configuration() {
    if (categoryAware && storageBinding == null) {
      throw ArgumentError('Categories require an explicitly bound stage.');
    }
  }

  final void Function(String)? migrationCheckpoint;
  final StorageBinding? storageBinding;
  @override
  int get schemaVersion => correctionsAware
      ? 13
      : notesAware
      ? 12
      : reversalsAware
      ? 11
      : refundsAware
      ? 10
      : fxTransfersAware
      ? 9
      : transfersAware
      ? 8
      : merchantsAware
      ? 7
      : tagsAware
      ? 6
      : categoryReferences
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
      if (fxTransfersAware) await customStatement(fxTransferSchema);
      if (refundsAware) {
        await customStatement(refundSchema);
        await customStatement(refundIndex);
      }
      if (reversalsAware) await customStatement(reversalSchema);
      if (notesAware) await customStatement(noteSchema);
      if (correctionsAware) await customStatement(correctionSchema);
      await _upgradeV2();
      if (storageBinding != null) await _upgradeV3();
      if (categoryAware) {
        for (final sql in categorySchema) {
          await customStatement(sql);
        }
        migrationCheckpoint?.call('categories');
      }
      if (tagsAware) {
        for (final sql in [...tagSchema, tagReferenceSchema]) {
          await customStatement(sql);
        }
        migrationCheckpoint?.call('tags');
      }
      if (merchantsAware) {
        for (final sql in [...merchantSchema, merchantReferenceSchema]) {
          await customStatement(sql);
        }
        migrationCheckpoint?.call('merchants');
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

const fxTransferColumns = ['workspace', 'event_id', 'context'];
const fxTransferSchema = '''CREATE TABLE event_fx (
 workspace TEXT NOT NULL, event_id TEXT NOT NULL, context TEXT NOT NULL,
 PRIMARY KEY(workspace,event_id),
 FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id)) STRICT''';

const refundColumns = ['workspace', 'event_id', 'original_id'];
const refundSchema = '''CREATE TABLE event_refunds (
 workspace TEXT NOT NULL, event_id TEXT NOT NULL, original_id TEXT NOT NULL,
 PRIMARY KEY(workspace,event_id),
 FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id),
 FOREIGN KEY(workspace,original_id) REFERENCES events(workspace,id)) STRICT''';
const refundIndex =
    'CREATE INDEX refunds_by_original ON event_refunds(workspace,original_id)';

const reversalColumns = ['workspace', 'event_id', 'original_id', 'reason'];
const reversalSchema = '''CREATE TABLE event_reversals (
 workspace TEXT NOT NULL, event_id TEXT NOT NULL, original_id TEXT NOT NULL,
 reason TEXT NOT NULL,
 PRIMARY KEY(workspace,event_id), UNIQUE(workspace,original_id),
 FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id),
 FOREIGN KEY(workspace,original_id) REFERENCES events(workspace,id)) STRICT''';

const noteColumns = [
  'workspace',
  'event_id',
  'revision',
  'operation_id',
  'text',
];
const noteSchema = '''CREATE TABLE event_note_revisions (
 workspace TEXT NOT NULL, event_id TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0),
 operation_id TEXT NOT NULL, text TEXT NOT NULL,
 PRIMARY KEY(workspace,event_id,revision), UNIQUE(workspace,operation_id),
 FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id)) STRICT''';

const correctionColumns = [
  'workspace',
  'original_id',
  'reversal_id',
  'replacement_id',
];
const correctionSchema = '''CREATE TABLE event_corrections (
 workspace TEXT NOT NULL, original_id TEXT NOT NULL,
 reversal_id TEXT NOT NULL, replacement_id TEXT NOT NULL,
 PRIMARY KEY(workspace,original_id),
 UNIQUE(workspace,reversal_id), UNIQUE(workspace,replacement_id),
 CHECK(original_id != reversal_id AND original_id != replacement_id AND reversal_id != replacement_id),
 FOREIGN KEY(workspace,original_id) REFERENCES events(workspace,id),
 FOREIGN KEY(workspace,reversal_id) REFERENCES events(workspace,id),
 FOREIGN KEY(workspace,replacement_id) REFERENCES events(workspace,id)) STRICT''';
