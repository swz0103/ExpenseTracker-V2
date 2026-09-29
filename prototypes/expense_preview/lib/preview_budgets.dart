part of 'preview_engine.dart';

extension PreviewBudgets on PreviewEngine {
  Future<List<BudgetPlan>> savedBudgets() => _exclusive((epoch) async {
    _require();
    if (!capabilities.budgets) throw PreviewInvalid();
    final plans = await _session!.budgets(_workspace!);
    _check(epoch);
    return plans;
  });

  Future<void> saveBudget(
    BudgetPlan plan,
    OperationId operation, {
    bool deleted = false,
  }) => _exclusive((epoch) async {
    _require();
    if (!capabilities.budgets || plan.workspace != _workspace) {
      throw PreviewInvalid();
    }
    await _session!.saveBudget(
      plan,
      operation,
      DateTime.now().toUtc(),
      deleted: deleted,
    );
    _check(epoch);
  });
}
