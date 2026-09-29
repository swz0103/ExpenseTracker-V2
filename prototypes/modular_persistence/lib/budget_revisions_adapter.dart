import 'package:budgets/budgets.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';

import 'database.dart';

final class BudgetRevision {
  const BudgetRevision({
    required this.plan,
    required this.operation,
    required this.recordedAt,
    required this.deleted,
  });

  final BudgetPlan plan;
  final OperationId operation;
  final DateTime recordedAt;
  final bool deleted;
}

/// Append-only plan authority. A repeated operation succeeds only if its
/// payload and state match exactly; stale versions and mutations after a
/// tombstone are rejected in the same SQL transaction.
Future<BudgetRevision> appendBudgetRevision(
  ProbeDatabase db,
  BudgetPlan plan,
  OperationId operation,
  DateTime recordedAt, {
  bool deleted = false,
}) async {
  if (!db.budgetsAware) throw UnsupportedError('Budget schema is unavailable');
  if (!recordedAt.isUtc)
    throw const FormatException('Budget audit time must be UTC');
  final payload = BudgetPlanCodec().encode(plan);
  return db.transaction(() async {
    final previousOperation = await db
        .customSelect(
          'SELECT * FROM budget_revisions WHERE workspace=? AND operation_id=?',
          variables: [
            Variable(plan.workspace.id.value),
            Variable(operation.id.value),
          ],
        )
        .get();
    if (previousOperation.isNotEmpty) {
      final previous = _read(previousOperation.single.data);
      if (previous.plan.id != plan.id ||
          previous.plan.version != plan.version ||
          BudgetPlanCodec().encode(previous.plan) != payload ||
          previous.deleted != deleted) {
        throw const FormatException('Budget operation conflict');
      }
      return previous;
    }
    final latest = await db
        .customSelect(
          'SELECT * FROM budget_revisions WHERE workspace=? AND id=? '
          'ORDER BY version DESC LIMIT 1',
          variables: [
            Variable(plan.workspace.id.value),
            Variable(plan.id.value),
          ],
        )
        .get();
    if (latest.isEmpty) {
      if (plan.version != 1 || deleted) {
        throw const FormatException('Invalid first budget revision');
      }
    } else {
      final prior = _read(latest.single.data);
      if (prior.deleted || plan.version != prior.plan.version + 1) {
        throw const FormatException('Stale or deleted budget plan');
      }
      if (deleted &&
          BudgetPlanCodec().encode(_withVersion(prior.plan, plan.version)) !=
              payload) {
        throw const FormatException('Deletion cannot modify a budget plan');
      }
    }
    await db.customStatement(
      'INSERT INTO budget_revisions '
      '(workspace,id,version,operation_id,recorded_at,state,payload) '
      'VALUES (?,?,?,?,?,?,?)',
      [
        plan.workspace.id.value,
        plan.id.value,
        plan.version,
        operation.id.value,
        recordedAt.toIso8601String(),
        deleted ? 'deleted' : 'active',
        payload,
      ],
    );
    return BudgetRevision(
      plan: plan,
      operation: operation,
      recordedAt: recordedAt,
      deleted: deleted,
    );
  });
}

Future<List<BudgetRevision>> budgetHistory(
  ProbeDatabase db,
  WorkspaceId workspace,
) async {
  if (!db.budgetsAware) throw UnsupportedError('Budget schema is unavailable');
  final rows = await db
      .customSelect(
        'SELECT * FROM budget_revisions WHERE workspace=? ORDER BY id,version',
        variables: [Variable(workspace.id.value)],
      )
      .get();
  return [for (final row in rows) _read(row.data)];
}

Future<List<BudgetPlan>> currentBudgetPlans(
  ProbeDatabase db,
  WorkspaceId workspace,
) async {
  final history = await budgetHistory(db, workspace);
  final latest = <PublicId, BudgetRevision>{};
  for (final revision in history) {
    latest[revision.plan.id] = revision;
  }
  return [
    for (final revision in latest.values)
      if (!revision.deleted) revision.plan,
  ];
}

/// Used by portable snapshot capture and staged restore before accepting a
/// generation. It verifies the complete immutable chain, including tombstones.
Future<void> validateBudgetRevisions(ProbeDatabase db) async {
  if (!db.budgetsAware) throw UnsupportedError('Budget schema is unavailable');
  final rows = await db
      .customSelect(
        'SELECT * FROM budget_revisions ORDER BY workspace,id,version',
      )
      .get();
  BudgetRevision? previous;
  for (final row in rows) {
    final revision = _read(row.data);
    final samePlan =
        previous != null &&
        previous.plan.workspace == revision.plan.workspace &&
        previous.plan.id == revision.plan.id;
    if (!samePlan) {
      if (revision.plan.version != 1 || revision.deleted) {
        throw const FormatException('Invalid first budget revision');
      }
    } else {
      if (previous.deleted ||
          revision.plan.version != previous.plan.version + 1) {
        throw const FormatException('Invalid budget revision sequence');
      }
      if (revision.deleted &&
          BudgetPlanCodec().encode(
                _withVersion(previous.plan, revision.plan.version),
              ) !=
              BudgetPlanCodec().encode(revision.plan)) {
        throw const FormatException('Invalid budget tombstone');
      }
    }
    previous = revision;
  }
}

BudgetRevision _read(Map<String, Object?> row) {
  final plan = BudgetPlanCodec().decode(row['payload'] as String);
  if (plan.workspace.id.value != row['workspace'] ||
      plan.id.value != row['id'] ||
      plan.version != row['version']) {
    throw const FormatException('Budget revision identity mismatch');
  }
  final recordedAt = DateTime.parse(row['recorded_at'] as String);
  if (!recordedAt.isUtc || recordedAt.toIso8601String() != row['recorded_at']) {
    throw const FormatException('Invalid budget audit time');
  }
  final state = row['state'];
  if (state != 'active' && state != 'deleted') {
    throw const FormatException('Invalid budget revision state');
  }
  return BudgetRevision(
    plan: plan,
    operation: OperationId.parse(row['operation_id'] as String),
    recordedAt: recordedAt,
    deleted: state == 'deleted',
  );
}

BudgetPlan _withVersion(BudgetPlan plan, int version) => BudgetPlan(
  id: plan.id,
  workspace: plan.workspace,
  month: plan.month,
  limit: plan.limit,
  version: version,
  categoryId: plan.categoryId,
  accountIds: plan.accountIds,
  tagIds: plan.tagIds,
  warningPercent: plan.warningPercent,
);
