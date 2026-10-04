part of 'ledger_store.dart';

/// Report and planning reads: monthly totals, home-currency values,
/// net worth, budgets and recurring entries.
extension ReportQueries on LedgerStore {
  /// Income and expense for [month] in [homeCurrency]: home-currency
  /// entries plus foreign ones at their booked home value (feature audit
  /// G-11). [unvalued] counts foreign entries booked without one.
  ({MonthlyTotal total, int unvalued}) homeMonthly(
    WorkspaceId workspace,
    ReportMonth month,
  ) {
    var income = Money(homeCurrency, BigInt.zero);
    var expense = income;
    var unvalued = 0;
    for (final fact in monthlyFacts(workspace, month)) {
      if (fact.income.currency != homeCurrency) {
        unvalued++;
        continue;
      }
      income += fact.income;
      expense += fact.expense;
    }
    return (total: MonthlyTotal(income, expense), unvalued: unvalued);
  }

  /// Net worth in [homeCurrency] at booked values: home-currency accounts
  /// at their balance, foreign ones at the home value of what is in them,
  /// with money going out at the account's average booked rate (G-11).
  /// [rate] values a foreign inflow booked without a home value, such as
  /// sale proceeds, for example at that day's market rate; an account it
  /// cannot value is listed in [unvalued] and left out of [total].
  ({Money total, List<Account> unvalued}) netWorth(
    WorkspaceId workspace, {
    Money? Function(Money amount, BusinessDate date)? rate,
  }) {
    var total = Money(homeCurrency, BigInt.zero);
    final unvalued = <Account>[];
    for (final account in accounts(workspace)) {
      if (!account.includeInNetWorth) continue;
      final value = account.currency == homeCurrency
          ? balance(account)
          : homeBalance(account, rate: rate);
      if (value == null) {
        unvalued.add(account);
      } else {
        total += value;
      }
    }
    return (total: total, unvalued: unvalued);
  }

  /// What a foreign-currency account holds, in [homeCurrency] at booked
  /// values; null when an inflow has no known value. See [netWorth].
  Money? homeBalance(
    Account account, {
    Money? Function(Money amount, BusinessDate date)? rate,
  }) {
    final rows = _store.select(
      'SELECT p.id, p.payload, group_concat(l.minor_units) AS legs '
      'FROM ledger_postings p JOIN ledger_legs l ON l.posting_id = p.id '
      'WHERE l.account_id = ? GROUP BY p.id ORDER BY p.date, p.id',
      [account.id.value],
    );
    var units = BigInt.zero;
    var cost = BigInt.zero;
    for (final row in rows) {
      final posting = _decodePosting(row['payload']);
      var change = BigInt.zero;
      for (final leg in (row['legs']! as String).split(',')) {
        change += BigInt.parse(leg);
      }
      final amount = Money(account.currency, change);
      if (change.isNegative && units > BigInt.zero) {
        // Out at the average booked rate.
        final out = -change > units ? units : -change;
        cost -= _divideRounded(cost * out, units);
        units -= out;
        if (units == BigInt.zero) cost = BigInt.zero;
        continue;
      }
      if (change == BigInt.zero) continue;
      var known = _bookedValue(posting, metadata(posting.id), amount);
      known ??= rate?.call(amount, posting.date);
      if (known == null || known.currency != homeCurrency) return null;
      units += change;
      cost += known.minorUnits;
    }
    return Money(homeCurrency, cost);
  }

  /// The booked home value of [amount], one posting's effect on a foreign
  /// account: from its home value, or from the rate of a transfer from or
  /// to a home-currency account.
  Money? _bookedValue(Posting posting, PostingMetadata meta, Money amount) {
    final home = meta.homeValue;
    if (home != null) {
      final sign = BigInt.from(amount.minorUnits.sign);
      return Money(homeCurrency, home.minorUnits * sign);
    }
    final rate = posting.conversion?.rate;
    if (rate == null) return null;
    if (rate.base == homeCurrency && rate.quote == amount.currency) {
      return rate.inverse().convert(amount);
    }
    if (rate.quote == homeCurrency && rate.base == amount.currency) {
      return rate.convert(amount);
    }
    return null;
  }

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

  /// Report facts for one month, in date order: the same facts monthly
  /// reports and budgets use.
  List<MonthlyFact> monthlyFacts(WorkspaceId workspace, ReportMonth month) {
    final rows = _store.select(
      'SELECT id, payload FROM ledger_postings WHERE workspace = ? '
      'AND date BETWEEN ? AND ? ORDER BY date, id',
      [workspace.toString(), '${month.first}', '${month.last}'],
    );
    return [
      for (final row in rows)
        _fact(
          _decodePosting(row['payload']),
          metadata(PublicId.parse(row['id']! as String)),
        ),
    ];
  }

  MonthlyFact _fact(Posting posting, PostingMetadata metadata) {
    var refunded = posting.refundOf;
    final reversed = posting.reversalOf;
    if (reversed != null) {
      final rows = _store.select(
        'SELECT refund_of FROM ledger_postings WHERE id = ?',
        [reversed.value],
      );
      final original = rows.single['refund_of'] as String?;
      if (original != null) refunded = PublicId.parse(original);
    }
    if (refunded == null) return reportFact(posting, metadata);
    final legs = _store.select(
      'SELECT account_id FROM ledger_legs WHERE posting_id = ? AND leg = 0',
      [refunded.value],
    );
    final account = PublicId.parse(legs.single['account_id']! as String);
    return reportFact(posting, metadata, account: account);
  }

  /// Every budget for [month] with what was spent against it: budgets
  /// set for that month, and repeating budgets that started by then.
  /// Merged categories count toward the category they were merged into.
  List<BudgetResult> budgetStatus(WorkspaceId workspace, ReportMonth month) {
    final rows = _store.select(
      'SELECT payload FROM plan_budgets WHERE workspace = ? AND month <= ? '
      'ORDER BY id',
      [workspace.toString(), _month(month)],
    );
    final plans = [
      for (final row in rows)
        BudgetPlanCodec().decode(row['payload']! as String),
    ];
    final catalog = CategoryCatalog.restore(workspace, categories(workspace));
    final facts = [
      for (final fact in monthlyFacts(workspace, month))
        BudgetFact(workspace: workspace, report: _canonical(fact, catalog)),
    ];
    return [
      for (final plan in plans)
        if (_month(plan.month) == _month(month) || plan.repeats)
          evaluateBudget(plan.forMonth(month), facts, categories: catalog),
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

  /// Category totals for `YYYY-MM`. Merged categories are reported under
  /// the category they were merged into.
  Map<(PublicId, String), MonthlyTotal> categoryTotals(
    WorkspaceId workspace,
    String month,
  ) {
    final catalog = CategoryCatalog.restore(workspace, categories(workspace));
    final rows = _store.select(
      'SELECT * FROM ledger_category_monthly WHERE workspace = ? AND month = ?',
      [workspace.toString(), month],
    );
    final totals = <(PublicId, String), MonthlyTotal>{};
    for (final row in rows) {
      final category = PublicId.parse(row['category_id'] as String);
      final key = (catalog.resolve(category).id, row['currency'] as String);
      final income = _money(row, 'income');
      final expense = _money(row, 'expense');
      final earlier = totals[key];
      totals[key] = earlier == null
          ? MonthlyTotal(income, expense)
          : MonthlyTotal(earlier.income + income, earlier.expense + expense);
    }
    return totals;
  }

  /// Totals for `YYYY-MM`, keyed by currency code.
  Map<String, MonthlyTotal> monthly(WorkspaceId workspace, String month) {
    final rows = _store.select(
      'SELECT * FROM ledger_monthly WHERE workspace = ? AND month = ?',
      [workspace.toString(), month],
    );
    return {
      for (final row in rows)
        row['currency'] as String: MonthlyTotal(
          _money(row, 'income'),
          _money(row, 'expense'),
        ),
    };
  }
}
