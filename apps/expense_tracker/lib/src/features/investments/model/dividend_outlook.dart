import 'returns.dart';

/// The dividends expected over the twelve months after today, as 股息
/// shows them: each month's sum by holding, the holdings by how much
/// they pay in all, and each month's total.
final class DividendOutlook {
  DividendOutlook._(this.months, this.byMonth, this.names, this.order);

  factory DividendOutlook.of(List<DividendGuess> guesses, DateTime today) {
    final months = [
      for (var k = 1; k <= 12; k++) DateTime.utc(today.year, today.month + k),
    ];
    // By month, then by holding; several from one holding in a month add
    // up.
    final byMonth = [for (final _ in months) <String, int>{}];
    for (final g in guesses) {
      final k = months.indexWhere(
        (m) => m.year == g.month.year && m.month == g.month.month,
      );
      if (k < 0) continue;
      byMonth[k][g.code] = (byMonth[k][g.code] ?? 0) + g.amount;
    }
    final totals = <String, int>{};
    for (final month in byMonth) {
      for (final MapEntry(:key, :value) in month.entries) {
        totals[key] = (totals[key] ?? 0) + value;
      }
    }
    return DividendOutlook._(months, byMonth, {
      for (final g in guesses) g.code: g.name,
    }, totals.keys.toList()..sort((a, b) => totals[b]!.compareTo(totals[a]!)));
  }

  /// The twelve months, each as its first day.
  final List<DateTime> months;

  /// Each month's dividends, by holding code.
  final List<Map<String, int>> byMonth;

  /// Each holding's name, by its code.
  final Map<String, String> names;

  /// The holdings, the one paying most in all first.
  final List<String> order;

  /// Each month's total.
  late final List<int> sums = [
    for (final m in byMonth) m.values.fold(0, (a, b) => a + b),
  ];

  /// The year's total.
  late final int total = sums.fold(0, (a, b) => a + b);

  /// The first month with any, or -1.
  late final int first = sums.indexWhere((s) => s > 0);
}
