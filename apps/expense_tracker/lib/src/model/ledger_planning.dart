part of 'ledger.dart';

/// Budgets and recurring items: what has been spent against a limit and
/// what falls due next.
extension LedgerPlanning on Ledger {
  /// What spending carrying [tag] came to in [year]/[month].
  int spentOnTag(String tag, int year, int month) {
    var total = 0;
    for (final e in entriesIn(year, month)) {
      if (e.tags.contains(tag)) total += e.spending;
    }
    return total;
  }

  Budget budgetFor(String category) => _budgets.firstWhere(
    (b) => b.category == category,
    orElse: () => Budget(category, 0),
  );

  /// The entries booking [item] in [year]/[month], earliest first.
  List<Entry> confirmationsIn(Recurring item, int year, int month) => [
    for (final e in entriesIn(year, month).reversed)
      if (e.recurring == item.id) e,
  ];

  /// The first day of this month [item] falls due and is not yet booked:
  /// bookings count against its days in order, so one booked early still
  /// settles that day.
  DateTime? pendingDate(Recurring item) {
    if (!item.active) return null;
    final dates = item.datesIn(today.year, today.month);
    final booked = confirmationsIn(item, today.year, today.month).length;
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
