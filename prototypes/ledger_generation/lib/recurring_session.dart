part of 'ledger_store.dart';

/// User-reviewed templates remain inert until an explicit posting command.
extension RecurringLedgerSession on LedgerSession {
  Future<RecurringRevision> saveRecurringTemplate(
    RecurringTemplate template,
    OperationId operation,
    DateTime recordedAt, {
    bool deleted = false,
  }) => _enqueue(
    () => _write(() async {
      if (!_db.recurringAware) {
        throw UnsupportedError('Recurring templates are unavailable');
      }
      final prior = await _db
          .customSelect(
            'SELECT 1 FROM recurring_revisions '
            'WHERE workspace=? AND operation_id=?',
            variables: [
              Variable.withString(template.workspace.id.value),
              Variable.withString(operation.id.value),
            ],
          )
          .get();
      if (prior.isEmpty) {
        await _admitCapacity();
        if (await _count('recurring_revisions') >=
            LedgerSession.maxRecurringChanges) {
          throw PreviewCapacity();
        }
      }
      final revision = await appendRecurringRevision(
        _db,
        template,
        operation,
        recordedAt,
        deleted: deleted,
      );
      if (prior.isEmpty) {
        await _checkRows(
          'recurring_revisions',
          'workspace=? AND operation_id=?',
          [template.workspace.id.value, operation.id.value],
        );
      }
      return revision;
    }),
  );

  Future<List<RecurringTemplate>> recurringTemplates(WorkspaceId workspace) =>
      _enqueue(() => currentRecurringTemplates(_db, workspace));

  /// The occurrence key and its Ledger event commit in one SQLite transaction.
  /// Re-reviewing a date returns the original event even after template edits.
  Future<({PublicId eventId, bool replayed})> confirmRecurring(
    RecurringCandidate candidate,
    PublicId eventId,
    OperationId operation,
    DateTime confirmedAt,
  ) => _enqueue(
    () => _write(() async {
      if (!_db.recurringAware) {
        throw UnsupportedError('Recurring templates are unavailable');
      }
      if (!confirmedAt.isUtc ||
          !isScheduledDate(candidate.template, candidate.dueDate)) {
        throw const FormatException('Invalid recurring confirmation');
      }
      final workspace = candidate.template.workspace;
      final existing = await _db
          .customSelect(
            'SELECT event_id FROM recurring_occurrences '
            'WHERE workspace=? AND template_id=? AND due_date=?',
            variables: [
              Variable.withString(workspace.id.value),
              Variable.withString(candidate.template.id.value),
              Variable.withString(candidate.dueDate.toString()),
            ],
          )
          .getSingleOrNull();
      if (existing != null) {
        return (
          eventId: PublicId.parse(existing.read<String>('event_id')),
          replayed: true,
        );
      }
      final current = (await currentRecurringTemplates(
        _db,
        workspace,
      )).where((item) => item.id == candidate.template.id).firstOrNull;
      if (current == null ||
          RecurringTemplateCodec().encode(current) !=
              RecurringTemplateCodec().encode(candidate.template)) {
        throw const FormatException('Stale recurring candidate');
      }
      final account = await AccountsAdapter(_db)
          .read(workspace, current.accountId);
      if (account.state != AccountState.active ||
          account.currency != current.amount.currency) {
        throw const FormatException('Recurring account is unavailable');
      }
      final ref = PostingAccount(
        id: account.id,
        workspace: workspace,
        currency: account.currency,
        expectedVersion: account.version,
      );
      final amount = current.amount;
      final posting = amount.minorUnits.isNegative
          ? Posting.expense(
              id: eventId,
              operation: OperationKey(workspace, operation),
              date: candidate.dueDate,
              account: ref,
              amount: -amount,
            )
          : Posting.income(
              id: eventId,
              operation: OperationKey(workspace, operation),
              date: candidate.dueDate,
              account: ref,
              amount: amount,
            );
      await _capacity(posting);
      final result = await FinancialWorkflows(
        _db,
        sourceContext: 'preview-recurring-v1',
      ).post(posting);
      if (result.replayed) {
        throw const FormatException('Recurring operation was already used');
      }
      await _checkFinancialRows(posting);
      await _db.customStatement(
        'INSERT INTO recurring_occurrences '
        '(workspace,template_id,due_date,template_version,event_id,operation_id,confirmed_at) '
        'VALUES (?,?,?,?,?,?,?)',
        [
          workspace.id.value,
          current.id.value,
          candidate.dueDate.toString(),
          current.version,
          eventId.value,
          operation.id.value,
          confirmedAt.toIso8601String(),
        ],
      );
      await _checkRows(
        'recurring_occurrences',
        'workspace=? AND template_id=? AND due_date=?',
        [workspace.id.value, current.id.value, candidate.dueDate.toString()],
      );
      return (eventId: eventId, replayed: false);
    }),
  );

  Future<List<RecurringCandidate>> recurringDue(
    WorkspaceId workspace, {
    required BusinessDate after,
    required BusinessDate through,
    int maxCandidates = 5000,
  }) => _enqueue(() async {
    if (maxCandidates < 1)
      throw const FormatException('Invalid candidate limit');
    final templates = await currentRecurringTemplates(_db, workspace);
    final confirmedRows = await _db
        .customSelect(
          'SELECT template_id,due_date FROM recurring_occurrences '
          'WHERE workspace=? AND due_date>? AND due_date<=?',
          variables: [
            Variable.withString(workspace.id.value),
            Variable.withString(after.toString()),
            Variable.withString(through.toString()),
          ],
        )
        .get();
    final confirmed = {
      for (final row in confirmedRows)
        (row.read<String>('template_id'), row.read<String>('due_date')),
    };
    final due = <RecurringCandidate>[];
    for (final template in templates) {
      final remaining = maxCandidates - due.length;
      final candidates = dueCandidates(
        template,
        after: after,
        through: through,
        // Confirmed dates do not use the visible limit. Permit their bounded
        // count while still failing when unconfirmed proposals exceed it.
        maxCandidates: remaining + confirmed.length == 0
            ? 1
            : remaining + confirmed.length,
      );
      due.addAll(
        candidates.where(
          (candidate) => !confirmed.contains((
            candidate.template.id.value,
            candidate.dueDate.toString(),
          )),
        ),
      );
      if (due.length > maxCandidates) {
        throw StateError('Candidate limit exceeded');
      }
    }
    due.sort((a, b) {
      final byDate = a.dueDate.compareTo(b.dueDate);
      return byDate != 0
          ? byDate
          : a.template.id.value.compareTo(b.template.id.value);
    });
    return List.unmodifiable(due);
  });
}
