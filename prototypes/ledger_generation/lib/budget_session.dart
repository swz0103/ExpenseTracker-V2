part of 'ledger_store.dart';

extension BudgetLedgerSession on LedgerSession {
  Future<BudgetRevision> saveBudget(
    BudgetPlan plan,
    OperationId operation,
    DateTime recordedAt, {
    bool deleted = false,
  }) => _enqueue(
    () => _write(() async {
      if (!_db.budgetsAware) throw UnsupportedError('Budgets are unavailable');
      final prior = await _db
          .customSelect(
            'SELECT 1 FROM budget_revisions WHERE workspace=? AND operation_id=?',
            variables: [
              Variable.withString(plan.workspace.id.value),
              Variable.withString(operation.id.value),
            ],
          )
          .get();
      if (prior.isEmpty) {
        await _admitCapacity();
        if (await _count('budget_revisions') >=
            LedgerSession.maxBudgetChanges) {
          throw PreviewCapacity();
        }
      }
      final revision = await appendBudgetRevision(
        _db,
        plan,
        operation,
        recordedAt,
        deleted: deleted,
      );
      if (prior.isEmpty) {
        await _checkRows('budget_revisions', 'workspace=? AND operation_id=?', [
          plan.workspace.id.value,
          operation.id.value,
        ]);
      }
      return revision;
    }),
  );

  Future<List<BudgetPlan>> budgets(WorkspaceId workspace) =>
      _enqueue(() => currentBudgetPlans(_db, workspace));

  Future<List<BudgetRevision>> budgetRevisions(WorkspaceId workspace) =>
      _enqueue(() => budgetHistory(_db, workspace));
}
