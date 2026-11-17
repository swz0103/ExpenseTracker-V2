part of 'ledger.dart';

// Questions asked of the entries again and again: a search, a day's
// entries, and a month's income, spending and spending by category.

extension LedgerQueries on Ledger {
  /// Entries of any month whose note, merchant, category or tags hold
  /// [words], or whose amount is [words]; newest first.
  List<Entry> search(String words) => _remember(
    ('search', words),
    () => _search(words),
    on: const {Topic.entries, Topic.accounts, Topic.categories},
  );

  List<Entry> _search(String words) {
    final lower = words.toLowerCase();
    // Each entry's words, lower-cased once per change.
    final texts = _remember(
      'searchText',
      () => [
        for (final e in _entries)
          [e.note, e.merchant, e.category, ...e.tags].join('\n').toLowerCase(),
      ],
      on: const {Topic.entries},
    );
    final found = [
      for (final (i, e) in _entries.indexed)
        if (texts[i].contains(lower) ||
            '${e.amount}' == words ||
            plainIn(e.amount, account(e.account).currency) == words)
          (i, e),
    ];
    found.sort((a, b) {
      final byDate = b.$2.date.compareTo(a.$2.date);
      return byDate != 0 ? byDate : b.$1.compareTo(a.$1);
    });
    return [for (final (_, e) in found) e];
  }

  /// Income of a month, dividends included.
  int income(int year, int month) =>
      entries.inMonth(year, month).fold(0, (total, e) => total + e.earning);

  /// Spending of a month, less refunds, with transfer fees.
  int expense(int year, int month, {int? untilDay}) => entries
      .inMonth(year, month)
      .where((e) => untilDay == null || e.date.day <= untilDay)
      .fold(0, (total, e) => total + e.spending);

  int dividends(int year, int month) =>
      entries.inMonth(year, month).fold(0, (sum, e) => sum + e.dividendNet);

  int spentOn(DateTime day) =>
      entries.onDay(day).fold(0, (total, e) => total + e.spending);

  /// A month's spending by category, largest first.
  List<(Category, int)> expenseByCategory(
    int year,
    int month, {
    int? untilDay,
  }) {
    final totals = <String, int>{};
    for (final e in entries.inMonth(year, month)) {
      if (untilDay != null && e.date.day > untilDay) continue;
      for (final (name, value) in e.spendingParts) {
        totals[name] = (totals[name] ?? 0) + value;
      }
    }
    final rows = [
      for (final MapEntry(:key, :value) in totals.entries)
        (category(key), value),
    ];
    rows.sort((a, b) => b.$2.compareTo(a.$2));
    return rows;
  }
}
