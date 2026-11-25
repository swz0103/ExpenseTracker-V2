import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fuzz.dart';

/// Review 32 1.2: the eight reads over the whole book (merchantStats,
/// merchants, lastUsedOn, tagStats, lastAt, usual, usualTransfers, tags)
/// are put together from counts kept a month at a time, so a save counts
/// its month again rather than the whole book. Whatever the book went
/// through (saves, edits, deletes and undo, a batch, a new day, 預定
/// entries coming due), each must equal what one pass over every entry
/// gave before: the old working, below, as the reference.
void main() {
  const accounts = [
    Account('cash', '現金', AccountKind.cash, 5000),
    Account('bank', '銀行', AccountKind.bank, 20000),
    Account('card', '卡', AccountKind.card, 0, closingDay: 10, dueDay: 25),
    Account('amy', 'Amy', AccountKind.receivable, 0),
  ];
  const merchants = ['全家', '7-11', '星巴克', '麥當勞', ''];
  const tags = ['家用', '出差', '旅行', '禮物'];

  for (var seed = 0; seed < fuzzSeeds; seed++) {
    test('the month counts give what every entry gave ($seed)', () {
      final r = Random(seed);
      var today = DateTime.utc(2026, 10, 15);
      var n = 0;
      T pick<T>(List<T> xs) => xs[r.nextInt(xs.length)];
      Entry make({String? id}) {
        final kind = r.nextInt(8);
        final type = switch (kind) {
          0 => EntryType.income,
          1 || 2 => EntryType.transfer,
          _ => EntryType.expense,
        };
        final account = pick(['cash', 'bank', 'card']);
        return Entry(
          id: id ?? 'e${n++}',
          // Over half a year back and a few weeks ahead (預定).
          date: today.add(Duration(days: r.nextInt(200) - 170)),
          type: type,
          amount: pick([100, 250, 999]) + (r.nextBool() ? 0 : r.nextInt(50)),
          account: type == EntryType.transfer
              ? pick(['cash', 'bank'])
              : account,
          to: type == EntryType.transfer ? pick(['bank', 'card', 'amy']) : null,
          category: switch (type) {
            EntryType.income => '薪資',
            EntryType.transfer => '',
            _ => pick(['飲食', '交通']),
          },
          merchant: type == EntryType.transfer ? '' : pick(merchants),
          tags: [for (var i = r.nextInt(3); i > 0; i--) pick(tags)],
        );
      }

      final ledger = Ledger(
        today: today,
        clock: () => today,
        accounts: accounts,
        categories: const [],
        entries: [for (var i = 0; i < 40; i++) make()],
        holdings: const [],
        budgets: const [],
        recurring: const [],
      );
      final removed = <Entry>[];
      void guard(void Function() f) {
        try {
          f();
        } on RecordRefused {
          // Refused: the book stays as it was.
        }
      }

      for (var step = 0; step < 50; step++) {
        final all = ledger.entries.all;
        switch (r.nextInt(9)) {
          case 0 || 1 || 2:
            guard(() => ledger.entryCommands.add(make()));
          case 3 when all.isNotEmpty:
            final e = pick(all);
            guard(() => ledger.entryCommands.replace(make(id: e.id)));
          case 4 when all.isNotEmpty:
            if (ledger.entryCommands.remove(pick(all).id) case final x?) {
              removed.add(x);
            }
          case 5 when removed.isNotEmpty:
            ledger.entryCommands.restore(
              removed.removeAt(r.nextInt(removed.length)),
            );
          case 6:
            // A batch, as an import adds.
            guard(
              () => ledger.entryCommands.addAll([
                for (var i = 0; i < 1 + r.nextInt(80); i++) make(),
              ]),
            );
          case 7:
            // A day or a week on: 預定 entries come due.
            today = today.add(Duration(days: pick([1, 7])));
            ledger.checkDay();
          default:
        }
        // Read only now and then, so changes pile up between reads.
        if (r.nextInt(3) > 0) {
          _expectAsBefore(ledger, merchants, 'seed $seed step $step');
        }
      }
    });
  }
}

void _expectAsBefore(Ledger ledger, List<String> merchants, String reason) {
  final before = _Before(ledger);
  final queries = ledger.entryQueryService;
  final reports = ledger.reportService;
  expect(
    [
      for (final MapEntry(:key, :value) in queries.lastUsedOn.entries)
        (key, value),
    ],
    [
      for (final MapEntry(:key, :value) in before.lastUsedOn().entries)
        (key, value),
    ],
    reason: '$reason lastUsedOn',
  );
  expect(queries.merchants, before.merchants(), reason: '$reason merchants');
  final latest = before.lastAt();
  for (final m in [...merchants, 'none']) {
    expect(
      identical(queries.lastAt(m), latest[m]),
      isTrue,
      reason: '$reason lastAt $m',
    );
  }
  List<String> ids(List<Entry> es) => [for (final e in es) e.id];
  for (final most in [6, 2]) {
    for (final income in [false, true]) {
      expect(
        ids(queries.usual(most: most, income: income)),
        ids(before.usual(most: most, income: income)),
        reason: '$reason usual $most $income',
      );
    }
    expect(
      ids(queries.usualTransfers(most: most)),
      ids(before.usualTransfers(most: most)),
      reason: '$reason usualTransfers $most',
    );
  }
  expect(reports.tagStats, before.tagStats(), reason: '$reason tagStats');
  expect(
    reports.merchantStats,
    before.merchantStats(),
    reason: '$reason merchantStats',
  );
  expect(reports.tags, before.tags(), reason: '$reason tags');
}

/// The eight reads as worked out before review 32 1.2: one pass over every
/// entry each.
final class _Before {
  _Before(this.ledger);

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
