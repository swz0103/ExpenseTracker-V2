import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:recurring_transactions/recurring_transactions.dart';

import 'database.dart';

final class RecurringRevision {
  const RecurringRevision({
    required this.template,
    required this.operation,
    required this.recordedAt,
    required this.deleted,
  });

  final RecurringTemplate template;
  final OperationId operation;
  final DateTime recordedAt;
  final bool deleted;
}

/// Append-only template authority. Retry returns the original receipt only
/// when the canonical payload and requested state are identical.
Future<RecurringRevision> appendRecurringRevision(
  ProbeDatabase db,
  RecurringTemplate template,
  OperationId operation,
  DateTime recordedAt, {
  bool deleted = false,
}) async {
  if (!db.recurringAware) {
    throw UnsupportedError('Recurring template schema is unavailable');
  }
  if (!recordedAt.isUtc) {
    throw const FormatException('Recurring audit time must be UTC');
  }
  final payload = RecurringTemplateCodec().encode(template);
  return db.transaction(() async {
    final previousOperation = await db
        .customSelect(
          'SELECT * FROM recurring_revisions WHERE workspace=? AND operation_id=?',
          variables: [
            Variable(template.workspace.id.value),
            Variable(operation.id.value),
          ],
        )
        .get();
    if (previousOperation.isNotEmpty) {
      final previous = _read(previousOperation.single.data);
      if (previous.template.id != template.id ||
          previous.template.version != template.version ||
          RecurringTemplateCodec().encode(previous.template) != payload ||
          previous.deleted != deleted) {
        throw const FormatException('Recurring operation conflict');
      }
      return previous;
    }
    final latest = await db
        .customSelect(
          'SELECT * FROM recurring_revisions WHERE workspace=? AND id=? '
          'ORDER BY version DESC LIMIT 1',
          variables: [
            Variable(template.workspace.id.value),
            Variable(template.id.value),
          ],
        )
        .get();
    if (latest.isEmpty) {
      if (template.version != 1 || deleted) {
        throw const FormatException('Invalid first recurring revision');
      }
    } else {
      final prior = _read(latest.single.data);
      if (prior.deleted || template.version != prior.template.version + 1) {
        throw const FormatException('Stale or deleted recurring template');
      }
      if (deleted &&
          RecurringTemplateCodec().encode(
                _withVersion(prior.template, template.version),
              ) !=
              payload) {
        throw const FormatException('Deletion cannot modify a template');
      }
    }
    await db.customStatement(
      'INSERT INTO recurring_revisions '
      '(workspace,id,version,account_id,operation_id,recorded_at,state,payload) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        template.workspace.id.value,
        template.id.value,
        template.version,
        template.accountId.value,
        operation.id.value,
        recordedAt.toIso8601String(),
        deleted ? 'deleted' : 'active',
        payload,
      ],
    );
    return RecurringRevision(
      template: template,
      operation: operation,
      recordedAt: recordedAt,
      deleted: deleted,
    );
  });
}

Future<List<RecurringRevision>> recurringHistory(
  ProbeDatabase db,
  WorkspaceId workspace,
) async {
  if (!db.recurringAware) {
    throw UnsupportedError('Recurring template schema is unavailable');
  }
  final rows = await db
      .customSelect(
        'SELECT * FROM recurring_revisions WHERE workspace=? ORDER BY id,version',
        variables: [Variable(workspace.id.value)],
      )
      .get();
  final revisions = [for (final row in rows) _read(row.data)];
  _validateChain(revisions);
  return revisions;
}

Future<List<RecurringTemplate>> currentRecurringTemplates(
  ProbeDatabase db,
  WorkspaceId workspace,
) async {
  final history = await recurringHistory(db, workspace);
  final latest = <PublicId, RecurringRevision>{};
  for (final revision in history) {
    latest[revision.template.id] = revision;
  }
  return [
    for (final revision in latest.values)
      if (!revision.deleted) revision.template,
  ];
}

/// Validate every stored revision before snapshot capture or stage acceptance.
Future<void> validateRecurringRevisions(ProbeDatabase db) async {
  if (!db.recurringAware) {
    throw UnsupportedError('Recurring template schema is unavailable');
  }
  final rows = await db
      .customSelect(
        'SELECT * FROM recurring_revisions ORDER BY workspace,id,version',
      )
      .get();
  _validateChain([for (final row in rows) _read(row.data)]);
}

void _validateChain(Iterable<RecurringRevision> revisions) {
  RecurringRevision? previous;
  for (final revision in revisions) {
    final sameTemplate =
        previous != null &&
        previous.template.workspace == revision.template.workspace &&
        previous.template.id == revision.template.id;
    if (!sameTemplate) {
      if (revision.template.version != 1 || revision.deleted) {
        throw const FormatException('Invalid first recurring revision');
      }
    } else {
      if (previous.deleted ||
          revision.template.version != previous.template.version + 1) {
        throw const FormatException('Invalid recurring revision sequence');
      }
      if (revision.deleted &&
          RecurringTemplateCodec().encode(
                _withVersion(previous.template, revision.template.version),
              ) !=
              RecurringTemplateCodec().encode(revision.template)) {
        throw const FormatException('Invalid recurring tombstone');
      }
    }
    previous = revision;
  }
}

RecurringRevision _read(Map<String, Object?> row) {
  final template = RecurringTemplateCodec().decode(row['payload'] as String);
  if (template.workspace.id.value != row['workspace'] ||
      template.id.value != row['id'] ||
      template.version != row['version'] ||
      template.accountId.value != row['account_id']) {
    throw const FormatException('Recurring revision identity mismatch');
  }
  final recordedAt = DateTime.parse(row['recorded_at'] as String);
  if (!recordedAt.isUtc || recordedAt.toIso8601String() != row['recorded_at']) {
    throw const FormatException('Invalid recurring audit time');
  }
  final state = row['state'];
  if (state != 'active' && state != 'deleted') {
    throw const FormatException('Invalid recurring revision state');
  }
  return RecurringRevision(
    template: template,
    operation: OperationId.parse(row['operation_id'] as String),
    recordedAt: recordedAt,
    deleted: state == 'deleted',
  );
}

RecurringTemplate _withVersion(RecurringTemplate template, int version) =>
    RecurringTemplate(
      id: template.id,
      workspace: template.workspace,
      accountId: template.accountId,
      label: template.label,
      amount: template.amount,
      firstDate: template.firstDate,
      unit: template.unit,
      every: template.every,
      version: version,
    );
