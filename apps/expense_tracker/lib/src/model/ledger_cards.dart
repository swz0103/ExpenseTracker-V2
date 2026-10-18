part of 'ledger.dart';

/// Card statements: what has been billed, what is due and what is not
/// billed yet. A statement closes at the end of its day.
extension LedgerCards on Ledger {
  /// How much of [e] has reached its card's statements by [at]: all of
  /// it, or the instalments billed so far.
  int billed(Entry e, DateTime at) => account(e.account).billed(e, at);

  /// How many instalments of [e] have been billed by [at].
  int billedPeriods(Entry e, DateTime at) =>
      account(e.account).billedPeriods(e, at);

  /// The last day whose statement closes are behind: a statement closes
  /// at the end of its day, so one closing today is still open.
  DateTime get closedBy => today.subtract(const Duration(days: 1));

  /// The last closed statement of [card]: its first and last day and when
  /// it must be paid.
  (DateTime, DateTime, DateTime) statement(Account card) {
    final end = card.closingOn(closedBy);
    final before = card.closingOn(end.subtract(const Duration(days: 1)));
    final start = before.add(const Duration(days: 1));
    // The due day in the close's month, or the next, kept within it.
    DateTime dueIn(int month) {
      final last = DateTime.utc(end.year, month + 1, 0);
      final day = min(card.dueDay ?? 15, last.day);
      return DateTime.utc(last.year, last.month, day);
    }

    final here = dueIn(end.month);
    return (start, end, here.isAfter(end) ? here : dueIn(end.month + 1));
  }

  /// What is still to pay on the last statement of [card]: the journal's
  /// figure once every change has reached it, else [dueFromEntries].
  int statementDue(Account card) {
    final kept = _dues[card.id];
    return kept != null && _waiting == 0 ? kept : dueFromEntries(card);
  }

  /// [statementDue] worked out from the entries, as the screens show it
  /// before a change has been kept.
  int dueFromEntries(Account card) {
    final (_, end, _) = statement(card);
    var paid = 0;
    for (final e in _entries) {
      if (e.type == EntryType.transfer &&
          e.to == card.id &&
          e.date.isAfter(end)) {
        paid += e.arrived;
      }
    }
    return max(0, -balance(card.id, until: end) - paid);
  }

  /// Purchases on [card] since its last statement closed, and the
  /// refunds and rewards credited against them.
  List<Entry> unbilled(Account card) {
    final (_, end, _) = statement(card);
    bool posted(Entry e) => switch (e.type) {
      EntryType.income => true,
      EntryType.expense => e.installments < 2,
      _ => false,
    };
    return [
      for (final e in _entries)
        if (e.account == card.id && posted(e) && e.date.isAfter(end)) e,
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Purchases on [card] still being paid in instalments.
  List<Entry> instalmentsOn(Account card) => [
    for (final e in _entries)
      if (e.account == card.id &&
          e.installments > 1 &&
          billedPeriods(e, closedBy) < e.installments)
        e,
  ];
}
