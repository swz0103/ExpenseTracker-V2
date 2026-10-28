part of 'ledger.dart';

/// Budgets and recurring items: what has been spent against a limit and
/// what falls due next.
extension LedgerPlanning on Ledger {
  /// The days of [year]/[month] gone by, today included, and all its
  /// days; every day of a month other than this one.
  (int, int) daysGone(int year, int month) {
    final days = DateTime.utc(year, month + 1, 0).day;
    final current = year == today.year && month == today.month;
    return (current ? today.day : days, days);
  }

  /// What spending carrying [tag] came to in [year]/[month].
  int spentOnTag(String tag, int year, int month) {
    var total = 0;
    for (final e in entriesIn(year, month)) {
      if (e.tags.contains(tag)) total += e.spending;
    }
    return total;
  }

  /// Where [spent] in [year]/[month] is heading by the month's end at the
  /// pace so far: the month's spending for a month gone by.
  int forecast(int spent, int year, int month) {
    final (passed, days) = daysGone(year, month);
    if (passed >= days || passed == 0) return spent;
    return (spent * days / passed).round();
  }

  Budget budgetFor(String category) => _budgets.firstWhere(
    (b) => b.category == category,
    orElse: () => Budget(category, 0),
  );

  /// What counts against [budget] in [year]/[month]: all spending, the
  /// spending carrying its tag, or its category's share of spending.
  int spentAgainst(Budget budget, int year, int month) {
    if (budget.category == Ledger.allSpending) return expense(year, month);
    if (budget.tag case final tag?) return spentOnTag(tag, year, month);
    var total = 0;
    for (final e in entriesIn(year, month)) {
      for (final (name, value) in e.spendingParts) {
        if (name == budget.category) total += value;
      }
    }
    return total;
  }

  /// [budget]'s limit for [year]/[month]: with [Budget.carry], plus what
  /// was left of it the month before, when it counted then. Only the
  /// month before: a leftover does not pile up.
  int allowance(Budget budget, int year, int month) {
    if (!budget.carry || budget.limit == 0) return budget.limit;
    final last = DateTime.utc(year, month - 1);
    final since = budget.since;
    if (since != null && last.isBefore(since)) return budget.limit;
    final left = budget.limit - spentAgainst(budget, last.year, last.month);
    return budget.limit + (left > 0 ? left : 0);
  }

  /// The entries booking [item] in [year]/[month], earliest first.
  List<Entry> confirmationsIn(Recurring item, int year, int month) => [
    for (final e in entriesIn(year, month).reversed)
      if (e.recurring == item.id) e,
  ];

  /// The first day [item] falls due and is not yet booked: one left over
  /// from last month, once the item has been booked before it, else this
  /// month's. Bookings count against a month's days in order, so one
  /// booked early still settles that day.
  DateTime? pendingDate(Recurring item) => _remember(
    ('pending', item.id, item.active, today),
    () => _pendingDate(item),
    on: const {Area.entries, Area.recurring},
  );

  DateTime? _pendingDate(Recurring item) {
    if (!item.active) return null;
    final last = DateTime.utc(today.year, today.month - 1);
    final missed = _unbooked(item, last.year, last.month);
    if (missed != null &&
        _entries.any(
          (e) => e.recurring == item.id && e.date.isBefore(missed),
        )) {
      return missed;
    }
    return _unbooked(item, today.year, today.month);
  }

  /// The first day of [year]/[month] [item] falls due that no booking of
  /// that month settles.
  DateTime? _unbooked(Recurring item, int year, int month) {
    final dates = item.datesIn(year, month);
    final booked = confirmationsIn(item, year, month).length;
    return booked < dates.length ? dates[booked] : null;
  }

  /// The next day [item] falls due, this month or later.
  DateTime? nextDate(Recurring item) {
    final pending = pendingDate(item);
    if (pending != null) return pending;
    for (var k = 1; k <= 24; k++) {
      final month = DateTime.utc(today.year, today.month + k);
      final dates = item.datesIn(month.year, month.month);
      if (dates.isNotEmpty) return dates.first;
    }
    return null;
  }

  /// [nextDate] as 「10/5」.
  String nextLabel(Recurring item) {
    final d = nextDate(item);
    return d == null ? '' : '${d.month}/${d.day}';
  }

  /// Active items whose day has come this month but are not yet booked.
  List<Recurring> get due => [
    for (final r in _recurring)
      if (pendingDate(r) case final d? when !d.isAfter(today)) r,
  ];

  /// Active items still to come this month, soonest first.
  List<Recurring> get upcoming {
    final rows = [
      for (final r in _recurring)
        if (pendingDate(r) case final d? when d.isAfter(today)) (r, d),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final (r, _) in rows) r];
  }
}
