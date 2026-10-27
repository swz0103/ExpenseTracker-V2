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
  (DateTime, DateTime, DateTime) statement(Account card) =>
      _remember(('statement', card.id, closedBy), () {
        final end = card.closingOn(closedBy);
        final (start, due) = card.cycleEnding(end);
        return (start, end, due);
      });

  /// What is still to pay on the last statement of [card]: what it owed
  /// when the statement closed, less what was paid in since.
  int statementDue(Account card) =>
      _remember(('due', card.id, closedBy), () => _statementDue(card));

  int _statementDue(Account card) {
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
  List<Entry> unbilled(Account card) =>
      _remember(('unbilled', card.id, closedBy), () => _unbilled(card));

  List<Entry> _unbilled(Account card) {
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
  List<Entry> instalmentsOn(Account card) => _remember(
    ('instalments', card.id, closedBy),
    () => [
      for (final e in _entries)
        if (e.account == card.id &&
            e.installments > 1 &&
            billedPeriods(e, closedBy) < e.installments)
          e,
    ],
  );
}
