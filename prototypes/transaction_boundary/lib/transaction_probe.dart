import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

enum Checkpoint { business, debit, credit, receipt, committed }

class OperationConflict implements Exception {
  const OperationConflict();
}

class ProbeResult {
  const ProbeResult(this.operationId, {required this.replayed});

  final String operationId;
  final bool replayed;
}

/// Fixed two-leg, same-currency fixture. Does not implement production Ledger.
class TransactionProbe {
  TransactionProbe(String path) : database = sqlite3.open(path) {
    database.execute('PRAGMA busy_timeout = 10000');
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('''
      CREATE TABLE IF NOT EXISTS business_operations (
        workspace_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        minor_units INTEGER NOT NULL CHECK (minor_units > 0),
        PRIMARY KEY (workspace_id, operation_id)
      ) STRICT;
      CREATE TABLE IF NOT EXISTS ledger_legs (
        workspace_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        side TEXT NOT NULL CHECK (side IN ('source', 'destination')),
        minor_units INTEGER NOT NULL,
        PRIMARY KEY (workspace_id, operation_id, side),
        FOREIGN KEY (workspace_id, operation_id)
          REFERENCES business_operations (workspace_id, operation_id)
      ) STRICT;
      CREATE TABLE IF NOT EXISTS operation_receipts (
        workspace_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        canonical_input TEXT NOT NULL,
        PRIMARY KEY (workspace_id, operation_id),
        FOREIGN KEY (workspace_id, operation_id)
          REFERENCES business_operations (workspace_id, operation_id)
      ) STRICT;
    ''');
  }

  final Database database;

  ProbeResult transfer({
    required String workspaceId,
    required String operationId,
    required int minorUnits,
    void Function(Checkpoint)? onCheckpoint,
  }) {
    if (workspaceId.isEmpty || operationId.isEmpty || minorUnits <= 0) {
      throw ArgumentError(
        'A workspace, operation ID and positive amount are required.',
      );
    }
    // An exact canonical fixture payload is sufficient here. Production must
    // version canonicalization for all command fields, not just the amount.
    final input = jsonEncode(['v1', 'transfer', minorUnits.toString()]);
    database.execute('BEGIN IMMEDIATE');
    var committed = false;
    try {
      final receipts = database.select(
        '''SELECT canonical_input FROM operation_receipts
           WHERE workspace_id = ? AND operation_id = ?''',
        [workspaceId, operationId],
      );
      if (receipts.isNotEmpty) {
        if (receipts.single['canonical_input'] != input) {
          throw const OperationConflict();
        }
        database.execute('COMMIT');
        committed = true;
        return ProbeResult(operationId, replayed: true);
      }

      database.execute('INSERT INTO business_operations VALUES (?, ?, ?)', [
        workspaceId,
        operationId,
        minorUnits,
      ]);
      onCheckpoint?.call(Checkpoint.business);
      database.execute('INSERT INTO ledger_legs VALUES (?, ?, ?, ?)', [
        workspaceId,
        operationId,
        'source',
        -minorUnits,
      ]);
      onCheckpoint?.call(Checkpoint.debit);
      database.execute('INSERT INTO ledger_legs VALUES (?, ?, ?, ?)', [
        workspaceId,
        operationId,
        'destination',
        minorUnits,
      ]);
      onCheckpoint?.call(Checkpoint.credit);
      database.execute('INSERT INTO operation_receipts VALUES (?, ?, ?)', [
        workspaceId,
        operationId,
        input,
      ]);
      onCheckpoint?.call(Checkpoint.receipt);
      database.execute('COMMIT');
      committed = true;
      onCheckpoint?.call(Checkpoint.committed);
      return ProbeResult(operationId, replayed: false);
    } catch (_) {
      if (!committed) {
        database.execute('ROLLBACK');
      }
      rethrow;
    }
  }

  void close() => database.close();
}
