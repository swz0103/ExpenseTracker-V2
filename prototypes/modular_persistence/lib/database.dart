import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Host integration fixture. Handwritten SQL, no reactive streams or encryption.
final class ProbeDatabase extends GeneratedDatabase {
  ProbeDatabase(File file) : super(NativeDatabase(file));
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final sql in _schema) {
        await customStatement(sql);
      }
    },
    onUpgrade: (_, from, to) async =>
        throw StateError('No migration from $from to $to.'),
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 10000');
    },
  );
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
