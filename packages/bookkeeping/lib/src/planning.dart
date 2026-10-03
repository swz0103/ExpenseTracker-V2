part of 'bookkeeping.dart';

/// Budgets and recurring templates stored next to the ledger.
abstract interface class PlanningTransaction implements BookkeepingTransaction {
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

  /// The template and due date [postingId] confirmed, if it did.
  Future<(PublicId, BusinessDate)?> confirmationOf(PublicId postingId);
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
        repeats: command.repeats,
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
        lastDate: command.lastDate,
        categoryId: command.categoryId,
        tagIds: command.tagIds,
        merchantId: command.merchantId,
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
    final expense = template.amount.minorUnits.isNegative;
    final value =
        command.amount ?? (expense ? -template.amount : template.amount);
    final date = command.date ?? command.dueDate;
    final account = await _books._postable(
      t,
      command.account,
      workspace,
      value.currency,
      date,
    );
    final flow = expense ? CashFlow.expense : CashFlow.income;
    final allocations = await _books._allocations(
      t,
      workspace,
      flow,
      command.allocations,
    );
    final posting = expense
        ? Posting.expense(
            id: command.postingId,
            operation: command.operation,
            date: date,
            account: account,
            amount: value,
            allocations: allocations,
          )
        : Posting.income(
            id: command.postingId,
            operation: command.operation,
            date: date,
            account: account,
            amount: value,
            allocations: allocations,
          );
    await _books._savePosting(
      t,
      posting,
      await _books._metadata(t, workspace, command.tags, command.merchant),
    );
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
///
/// [account] is the account the report amounts belong to. It defaults to
/// the posting's own account; a refund, or the reversal of one, reports
/// against the original expense's account, because its amounts are in
/// that expense's currency even when the money arrived elsewhere
/// (health check G6-18).
MonthlyFact reportFact(
  Posting posting,
  PostingMetadata metadata, {
  PublicId? account,
}) {
  return MonthlyFact(
    id: posting.id,
    date: posting.date,
    kind: posting.kind,
    income: posting.reportIncome,
    expense: posting.reportExpense,
    accountId: account ?? _reportAccount(posting),
    merchantId: metadata.merchantId,
    allocations: [
      for (final allocation in posting.allocations)
        CategoryAllocation(allocation.categoryId, allocation.amount),
    ],
    tagIds: metadata.tags.toSet(),
  );
}

/// A transfer reports its fee against the account that paid it, which is
/// the destination when the fee is in the destination currency (G-17).
PublicId _reportAccount(Posting posting) {
  for (final leg in posting.legs) {
    if (leg.role == LegRole.fee) return leg.account.id;
  }
  return posting.legs.first.account.id;
}
