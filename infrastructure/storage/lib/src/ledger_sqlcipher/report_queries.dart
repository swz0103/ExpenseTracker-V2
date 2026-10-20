part of 'ledger_store.dart';

/// Planning reads: recurring templates and the occurrences due.
extension ReportQueries on LedgerStore {
  /// Recurring templates in [workspace], with whether each is active.
  List<(RecurringTemplate, bool)> recurringTemplates(WorkspaceId workspace) {
    final rows = _store.select(
      'SELECT payload, active FROM plan_recurring WHERE workspace = ? '
      'ORDER BY id',
      [workspace.toString()],
    );
    final codec = RecurringTemplateCodec();
    return [
      for (final row in rows)
        (codec.decode(row['payload']! as String), row['active'] == 1),
    ];
  }

  /// Occurrences due after [after] up to [through] that are not confirmed
  /// yet, from active templates.
  List<RecurringCandidate> dueRecurring(
    WorkspaceId workspace, {
    required BusinessDate after,
    required BusinessDate through,
  }) {
    final rows = _store.select(
      'SELECT payload FROM plan_recurring '
      'WHERE workspace = ? AND active = 1 ORDER BY id',
      [workspace.toString()],
    );
    final confirmed = {
      for (final row in _store.select(
        'SELECT template_id, due_date FROM plan_recurring_confirmed',
      ))
        '${row['template_id']}/${row['due_date']}',
    };
    return [
      for (final row in rows)
        for (final candidate in dueCandidates(
          RecurringTemplateCodec().decode(row['payload']! as String),
          after: after,
          through: through,
        ))
          if (!confirmed.contains(
            '${candidate.template.id.value}/${candidate.dueDate}',
          ))
            candidate,
    ];
  }
}
