import '../../../core/ledger/ledger.dart';

/// What a stretch of days came to: income, spending, and spending by
/// category.
final class PeriodSums {
  const PeriodSums(this.income, this.expense, this.byCategory);

  final int income;
  final int expense;
  final Map<String, int> byCategory;

  int get left => income - expense;
}

/// The sums of the days from [from] to [to], both counted.
PeriodSums sumsBetween(Ledger ledger, DateTime from, DateTime to) {
  var income = 0;
  var expense = 0;
  final byCategory = <String, int>{};
  for (
    var m = DateTime.utc(from.year, from.month);
    !m.isAfter(to);
    m = DateTime.utc(m.year, m.month + 1)
  ) {
    for (final e in ledger.entriesIn(m.year, m.month)) {
      if (e.date.isBefore(from) || e.date.isAfter(to)) continue;
      income += e.earning;
      expense += e.spending;
      for (final (name, value) in e.spendingParts) {
        byCategory[name] = (byCategory[name] ?? 0) + value;
      }
    }
  }
  return PeriodSums(income, expense, byCategory);
}

/// One line of a comparison: what it is, and its amount in each period.
typedef CompareRow = (String, int, int);

/// Two periods side by side: income, spending and what was left, then
/// each category spent on in either, the largest difference first.
List<CompareRow> compare(PeriodSums a, PeriodSums b) {
  int gap(String n) => ((a.byCategory[n] ?? 0) - (b.byCategory[n] ?? 0)).abs();
  final names = {...a.byCategory.keys, ...b.byCategory.keys}.toList()
    ..sort((x, y) => gap(y).compareTo(gap(x)));
  return [
    ('收入', a.income, b.income),
    ('支出', a.expense, b.expense),
    ('結餘', a.left, b.left),
    for (final n in names) (n, a.byCategory[n] ?? 0, b.byCategory[n] ?? 0),
  ];
}
