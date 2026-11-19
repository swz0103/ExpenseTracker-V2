import '../../../core/ledger/ledger.dart';
import '../../../core/text/words.dart';

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
  final reports = ledger.reportService;
  final (income, expense) = reports.totalsBetween(from, to);
  return PeriodSums(income, expense, reports.spendingBetween(from, to));
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
    (Words.income, a.income, b.income),
    (Words.expense, a.expense, b.expense),
    ('結餘', a.left, b.left),
    for (final n in names) (n, a.byCategory[n] ?? 0, b.byCategory[n] ?? 0),
  ];
}
