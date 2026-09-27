import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'database.dart';

final class OperationConflict implements Exception {}

final class CommitResult {
  const CommitResult(this.id, {required this.replayed});
  final PublicId id;
  final bool replayed;
}

/// Shared transaction and operation namespace for financial and metadata writes.
final class OperationWriter {
  OperationWriter(this.db);
  final ProbeDatabase db;

  Future<CommitResult> commit(
    OperationKey operation,
    String input,
    PublicId proposedId,
    Future<void> Function() write,
    String kind,
    void Function(String)? checkpoint,
  ) => db.transaction(() async {
    final ws = operation.workspace.toString();
    final op = operation.operation.toString();
    final existing = await db
        .customSelect(
          'SELECT input,result_id FROM receipts WHERE workspace = ? AND operation_id = ?',
          variables: [Variable.withString(ws), Variable.withString(op)],
        )
        .get();
    if (existing.isNotEmpty) {
      if (existing.single.read<String>('input') != input)
        throw OperationConflict();
      return CommitResult(
        PublicId.parse(existing.single.read<String>('result_id')),
        replayed: true,
      );
    }
    await write();
    await db.customStatement('INSERT INTO receipts VALUES (?,?,?,?)', [
      ws,
      op,
      input,
      proposedId.value,
    ]);
    checkpoint?.call('receipt');
    await db.customStatement('INSERT INTO audit VALUES (?,?,?,?,?)', [
      ws,
      op,
      proposedId.value,
      kind,
      UtcInstant(DateTime.now()).toString(),
    ]);
    checkpoint?.call('audit');
    return CommitResult(proposedId, replayed: false);
  });
}
