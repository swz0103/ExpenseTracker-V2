part of 'bookkeeping.dart';

/// Budgets and recurring templates stored next to the ledger.
abstract interface class PlanningTransaction
    implements BookkeepingTransaction {
  Future<BudgetPlan?> budget(PublicId id);

  Future<void> saveBudget(BudgetPlan plan);

  /// The template and whether it still proposes occurrences.
  Future<(RecurringTemplate, bool)?> recurring(PublicId id);

  Future<void> saveRecurring(
    RecurringTemplate template, {
    required bool active,
  });

  /// The posting that confirmed [dueDate] of [templateId], if any.
  Future<PublicId?> confirmation(PublicId templateId, BusinessDate dueDate);

  Future<void> saveConfirmation(
    PublicId templateId,
    BusinessDate dueDate,
    PublicId postingId,
  );
}

/// Budget and recurring commands. Budgets are read models over the same
/// report facts as monthly reports; a recurring template only proposes,
/// and each confirmation is an ordinary income or expense.
final class PlanningBook<T extends PlanningTransaction> {
  PlanningBook(this._books);

  final Bookkeeping<T> _books;

  CommandRunner<T> get _runner => _books._runner;

  Future<CommandOutcome<int>> setBudget(SetBudget command) =>
      _runner.run(command, (t) => _guard(() => _setBudget(t, command)));

  Future<CommandOutcome<int>> saveRecurring(SaveRecurring command) =>
      _runner.run(command, (t) => _guard(() => _saveRecurring(t, command)));

  Future<CommandOutcome<PublicId>> confirm(ConfirmRecurring command) =>
      _runner.run(command, (t) => _guard(() => _confirm(t, command)));

  Future<int> _setBudget(T t, SetBudget command) async {
    final workspace = command.operation.workspace;
    final current = await t.budget(command.budgetId);
    if (current != null && current.workspace != workspace) {
      throw const AppFailure(FailureKind.notFound, 'budget.not-found');
    }
    if ((current?.version ?? 0) != command.expectedVersion) {
      throw const AppFailure(FailureKind.conflict, 'budget.versionConflict');
    }
    final categoryId = command.categoryId;
    if (categoryId != null) {
      final catalog = CategoryCatalog.restore(
        workspace,
        await t.categories(workspace),
      );
      if (catalog.get(categoryId).kind != CategoryKind.expense) {
        throw const AppFailure(FailureKind.rejected, 'budget.category-kind');
      }
    }
    final BudgetPlan plan;
    try {
      plan = BudgetPlan(
        id: command.budgetId,
        workspace: workspace,
        month: command.month,
        limit: command.limit,
        version: command.expectedVersion + 1,
        categoryId: categoryId,
        accountIds: command.accountIds,
        tagIds: command.tagIds,
        warningPercent: command.warningPercent,
      );
    } on FormatException {
      throw const AppFailure(FailureKind.rejected, 'budget.invalid');
    }
    await t.saveBudget(plan);
    await t.appendEvent(
      id: PublicId.generate(),
      workspace: workspace,
      kind: 'budget.set',
      payload: jsonEncode({'plan': BudgetPlanCodec().encode(plan)}),
    );
    return plan.version;
  }

  Future<int> _saveRecurring(T t, SaveRecurring command) async {
    final workspace = command.operation.workspace;
    final current = await t.recurring(command.templateId);
    if (current != null && current.$1.workspace != workspace) {
      throw const AppFailure(FailureKind.notFound, 'recurring.not-found');
    }
    if ((current?.$1.version ?? 0) != command.expectedVersion) {
      throw const AppFailure(FailureKind.conflict, 'recurring.versionConflict');
    }
    final account = await _books._account(t, command.accountId);
    if (account.workspace != workspace ||
        account.currency != command.amount.currency) {
      throw const AppFailure(FailureKind.rejected, 'recurring.account');
    }
    final RecurringTemplate template;
    try {
      template = RecurringTemplate(
        id: command.templateId,
        workspace: workspace,
        accountId: command.accountId,
        label: command.label,
        amount: command.amount,
        firstDate: command.firstDate,
        unit: command.unit,
        every: command.every,
        version: command.expectedVersion + 1,
      );
    } on FormatException {
      throw const AppFailure(FailureKind.rejected, 'recurring.invalid');
    }
    await t.saveRecurring(template, active: command.active);
    await t.appendEvent(
      id: PublicId.generate(),
      workspace: workspace,
      kind: 'recurring.saved',
      payload: jsonEncode({
        'template': RecurringTemplateCodec().encode(template),
        'active': command.active,
      }),
    );
    return template.version;
  }

  Future<PublicId> _confirm(T t, ConfirmRecurring command) async {
    final workspace = command.operation.workspace;
    await _books._requireNewPosting(t, command.postingId);
    final saved = await t.recurring(command.templateId);
    if (saved == null || saved.$1.workspace != workspace) {
      throw const AppFailure(FailureKind.notFound, 'recurring.not-found');
    }
    final (template, active) = saved;
    if (template.version != command.expectedTemplateVersion) {
      throw const AppFailure(FailureKind.conflict, 'recurring.versionConflict');
    }
    if (!active) {
      throw const AppFailure(FailureKind.rejected, 'recurring.stopped');
    }
    if (!isScheduledDate(template, command.dueDate)) {
      throw const AppFailure(FailureKind.rejected, 'recurring.not-due');
    }
    if (await t.confirmation(template.id, command.dueDate) != null) {
      throw const AppFailure(FailureKind.conflict, 'recurring.confirmed');
    }
    if (command.account.id != template.accountId) {
      throw const AppFailure(FailureKind.rejected, 'recurring.account');
    }
    final amount = template.amount;
    final expense = amount.minorUnits.isNegative;
    final value = expense ? -amount : amount;
    final account = await _books._postable(
      t,
      command.account,
      workspace,
      value.currency,
      command.dueDate,
    );
    final posting = expense
        ? Posting.expense(
            id: command.postingId,
            operation: command.operation,
            date: command.dueDate,
            account: account,
            amount: value,
          )
        : Posting.income(
            id: command.postingId,
            operation: command.operation,
            date: command.dueDate,
            account: account,
            amount: value,
          );
    await _books._savePosting(t, posting, PostingMetadata.none);
    await t.saveConfirmation(template.id, command.dueDate, posting.id);
    await t.appendEvent(
      id: PublicId.generate(),
      workspace: workspace,
      kind: 'recurring.confirmed',
      payload: jsonEncode({
        'templateId': template.id.value,
        'dueDate': command.dueDate.toString(),
        'postingId': posting.id.value,
      }),
    );
    return posting.id;
  }
}

/// The report fact for one posting: the single mapping from postings to
/// monthly reports and budgets (health check G1-01).
MonthlyFact reportFact(Posting posting, PostingMetadata metadata) {
  return MonthlyFact(
    id: posting.id,
    date: posting.date,
    kind: posting.kind,
    income: posting.reportIncome,
    expense: posting.reportExpense,
    accountId: posting.legs.first.account.id,
    merchantId: metadata.merchantId,
    allocations: [
      for (final allocation in posting.allocations)
        CategoryAllocation(allocation.categoryId, allocation.amount),
    ],
    tagIds: metadata.tags.toSet(),
  );
}
