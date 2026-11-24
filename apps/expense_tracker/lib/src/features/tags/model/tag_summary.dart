import '../../../core/ledger/ledger.dart';

/// A tag seen as a project, such as a trip or a renovation: when it ran
/// (its first and last entry), what was spent and by which category.
final class TagSummary {
  const TagSummary({
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

/// [tag] as a project on [today]; null when no entry carries it. Its
/// days and sums are of the entries that count today ([countsOn]): a 預定
/// one joins them on its day (D71), and stands in [TagSummary.entries]
/// from the start. With only 預定 entries, it runs over their days and
/// nothing is spent yet.
TagSummary? tagSummaryOf(EntryReader book, String tag, DateTime today) {
  final entries = [
    // Exception to as-of-today: the list holds every entry carrying the
    // tag, 預定 ones marked; the sums below take only those that count.
    for (final e in book.all)
      if (e.tags.contains(tag)) e,
  ]..sort(newestFirst(book));
  if (entries.isEmpty) return null;
  final counted = countedOn(entries, today).toList();
  final span = counted.isEmpty ? entries : counted;
  var spent = 0;
  var income = 0;
  final byCategory = <String, int>{};
  for (final e in counted) {
    spent += e.spending;
    income += e.earning;
    for (final (name, value) in e.spendingParts) {
      byCategory[name] = (byCategory[name] ?? 0) + value;
    }
  }
  return TagSummary(
    tag: tag,
    from: span.last.date,
    to: span.first.date,
    spent: spent,
    income: income,
    byCategory: [
      for (final MapEntry(:key, :value) in byCategory.entries) (key, value),
    ]..sort((a, b) => b.$2.compareTo(a.$2)),
    entries: entries,
  );
}

/// The tag of the latest entry that has one and counts on [today]
/// ([countsOn]): 標籤與商家's cover. A 預定 entry is not the latest.
String? latestTag(EntryReader book, DateTime today) {
  Entry? latest;
  for (final e in countedOn(book.all, today)) {
    if (e.tags.isEmpty) continue;
    if (latest == null || e.date.isAfter(latest.date)) latest = e;
  }
  return latest?.tags.first;
}

/// Each tag in use under the year of its latest entry, latest years first
/// and, in a year, latest tags first.
List<(int, List<String>)> tagsByYear(EntryReader book) {
  final last = <String, DateTime>{};
  // Exception to as-of-today: an index of every tag, to open each; a tag
  // only on 預定 entries sits under their year. Nothing is summed.
  for (final e in book.all) {
    for (final tag in e.tags) {
      final seen = last[tag];
      if (seen == null || e.date.isAfter(seen)) last[tag] = e.date;
    }
  }
  final tags = last.keys.toList()..sort((a, b) => last[b]!.compareTo(last[a]!));
  final years = <int, List<String>>{};
  for (final tag in tags) {
    (years[last[tag]!.year] ??= []).add(tag);
  }
  return [for (final MapEntry(:key, :value) in years.entries) (key, value)];
}

/// A merchant's visits, newest first; empty when none.
List<Entry> visitsTo(EntryReader book, String merchant) => [
  // Exception to as-of-today: a list of every visit, 預定 ones marked.
  for (final e in book.all)
    if (e.merchant == merchant) e,
]..sort(newestFirst(book));
