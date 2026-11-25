import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';

/// The day the trade books below are read on.
final tradeBookToday = DateTime.utc(2026, 10, 4);

/// A book of 100,000 entries, 3,000 of them trades of twenty stocks
/// (1101 to 1120) over three years: a buy of 1,000 shares every 10 days
/// and a sale of 500 every 20, the rest spending. What the trade gates
/// check sales against.
Ledger tradeBook() {
  final today = tradeBookToday;
  final r = Random(7);
  final entries = <Entry>[];
  for (var s = 0; s < 20; s++) {
    for (var k = 0; k < 100; k++) {
      final date = today.subtract(Duration(days: 1000 - k * 10 - s % 7));
      entries.add(
        Entry(
          id: 'b$s-$k',
          date: date,
          type: EntryType.buy,
          amount: 50000,
          account: 'bank',
          holding: '${1101 + s}',
          shares: 1000,
        ),
      );
      if (k.isOdd) {
        entries.add(
          Entry(
            id: 's$s-$k',
            date: date.add(const Duration(days: 1)),
            type: EntryType.sell,
            amount: 30000,
            account: 'bank',
            holding: '${1101 + s}',
            shares: 500,
          ),
        );
      }
    }
  }
  for (var i = entries.length; i < 100000; i++) {
    entries.add(
      Entry(
        id: 'e$i',
        date: today.subtract(Duration(days: r.nextInt(1000))),
        type: EntryType.expense,
        amount: 30 + r.nextInt(2000),
        account: 'bank',
        category: '飲食',
      ),
    );
  }
  return Ledger(
    today: today,
    accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
    categories: const [],
    entries: entries,
    holdings: const [],
    budgets: const [],
    recurring: const [],
  );
}

/// Whether [extra] can join [ledger]'s entries in place of [replacing],
/// worked out as `EntryValidator.holdsWith` did before FIX-R34: the whole
/// book replayed with the change. What the trade gates measure against.
bool wholeBookHolds(Ledger ledger, List<Entry> extra, {Entry? replacing}) =>
    ledger.holdings.holdsWith([
      for (final e in ledger.entries.all)
        if (replacing == null || e.id != replacing.id) e,
      ...extra,
    ]);
