import 'package:expense_tracker/src/core/ledger/ledger.dart';

/// The eight reads over the whole book as worked out before review 32
/// 1.2, one pass over every entry each: what the month counts must equal
/// (month_tallies_test), and what the gate measures them against.
final class WholeBookReads {
  WholeBookReads(this.ledger);

  final Ledger ledger;

  DateTime get today => ledger.today;
  List<Entry> get all => ledger.entries.all;

  Map<String, DateTime> lastUsedOn() {
    final last = <String, DateTime>{};
    for (final e in countedOn(all, today)) {
      for (final id in [e.account, ?e.to]) {
        final seen = last[id];
        if (seen == null || e.date.isAfter(seen)) last[id] = e.date;
      }
    }
    return last;
  }

  List<String> merchants() {
    final counts = <String, int>{
      for (final e in all)
        if (e.merchant.isNotEmpty) e.merchant: 0,
    };
    for (final e in countedOn(all, today)) {
      if (e.merchant.isEmpty) continue;
      counts[e.merchant] = (counts[e.merchant] ?? 0) + 1;
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  Map<String, Entry> lastAt() {
    final latest = <String, Entry>{};
    for (final e in countedOn(all, today)) {
      if (e.merchant.isEmpty || e.type != EntryType.expense) continue;
      final kept = latest[e.merchant];
      if (kept == null || !e.date.isBefore(kept.date)) latest[e.merchant] = e;
    }
    return latest;
  }

  List<Entry> usual({int most = 6, bool income = false}) {
    final since = today.subtract(const Duration(days: 90));
    final counts = <(String, String, String), int>{};
    final latest = <(String, String, String), Entry>{};
    final kind = income ? EntryType.income : EntryType.expense;
    for (final e in countedOn(all, today)) {
      if (e.type != kind ||
          e.refundOf != null ||
          e.date.isBefore(since) ||
          e.parts.isNotEmpty ||
          e.installments > 1 ||
          e.home != null) {
        continue;
      }
      final key = (e.category, e.merchant, e.account);
      counts[key] = (counts[key] ?? 0) + 1;
      final kept = latest[key];
      if (kept == null || !e.date.isBefore(kept.date)) latest[key] = e;
    }
    final keys = [
      for (final MapEntry(:key, :value) in counts.entries)
        if (value >= 3) key,
    ]..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return [for (final key in keys.take(most)) latest[key]!];
  }

  List<Entry> usualTransfers({int most = 4}) {
    final since = today.subtract(const Duration(days: 90));
    final counts = <(String, String, int), int>{};
    final latest = <(String, String, int), Entry>{};
    for (final e in countedOn(all, today)) {
      final to = e.to;
      if (e.type != EntryType.transfer ||
          to == null ||
          e.date.isBefore(since) ||
          ledger.account(e.account).kind == AccountKind.receivable ||
          ledger.account(to).kind == AccountKind.receivable) {
        continue;
      }
      final key = (e.account, to, e.amount);
      counts[key] = (counts[key] ?? 0) + 1;
      final kept = latest[key];
      if (kept == null || !e.date.isBefore(kept.date)) latest[key] = e;
    }
    final keys = [
      for (final MapEntry(:key, :value) in counts.entries)
        if (value >= 2) key,
    ]..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return [for (final key in keys.take(most)) latest[key]!];
  }

  List<(String, int, int)> tagStats() {
    final counts = <String, int>{};
    final sums = <String, int>{};
    for (final e in countedOn(all, today)) {
      for (final tag in e.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
        sums[tag] = (sums[tag] ?? 0) + e.spending;
      }
    }
    return [
      for (final MapEntry(:key, :value) in counts.entries)
        (key, value, sums[key] ?? 0),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
  }

  /// merchantsBetween is the old reading, kept for any stretch of days.
  List<(String, int, int)> merchantStats() =>
      ledger.reportService.merchantsBetween(
        ledger.reportService.firstDay,
        today,
      )..sort((a, b) => b.$2.compareTo(a.$2));

  List<String> tags() {
    final used = [for (final (tag, _, _) in tagStats()) tag];
    final known = {for (final e in all) ...e.tags};
    return [...used, ...known.difference(used.toSet())];
  }
}
