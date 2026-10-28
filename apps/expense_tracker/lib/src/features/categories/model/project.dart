import '../../../core/ledger/ledger.dart';

/// A tag seen as a project, such as a trip or a renovation: when it ran
/// (its first and last entry), what was spent and by which category.
final class Project {
  const Project({
    required this.tag,
    required this.from,
    required this.to,
    required this.spent,
    required this.income,
    required this.byCategory,
    required this.entries,
  });

  final String tag;

  /// The days of its first and last entry.
  final DateTime from;
  final DateTime to;
  final int spent;
  final int income;

  /// Spending by category, largest first.
  final List<(String, int)> byCategory;

  /// Its entries, newest first.
  final List<Entry> entries;

  /// Days from the first entry to the last, both counted.
  int get days => to.difference(from).inDays + 1;

  /// Spending a day over [days].
  int get perDay => spent ~/ days;
}

/// [tag] as a project; null when no entry carries it.
Project? projectOf(Ledger ledger, String tag) {
  final entries = [
    for (final e in ledger.entries)
      if (e.tags.contains(tag)) e,
  ]..sort((a, b) => b.date.compareTo(a.date));
  if (entries.isEmpty) return null;
  var spent = 0;
  var income = 0;
  final byCategory = <String, int>{};
  for (final e in entries) {
    spent += e.spending;
    income += e.earning;
    for (final (name, value) in e.spendingParts) {
      byCategory[name] = (byCategory[name] ?? 0) + value;
    }
  }
  return Project(
    tag: tag,
    from: entries.last.date,
    to: entries.first.date,
    spent: spent,
    income: income,
    byCategory: [
      for (final MapEntry(:key, :value) in byCategory.entries) (key, value),
    ]..sort((a, b) => b.$2.compareTo(a.$2)),
    entries: entries,
  );
}
