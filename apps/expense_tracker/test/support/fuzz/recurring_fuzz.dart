import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fuzz.dart';
import 'restore_invariants.dart';

/// Seeded runs, [fuzzSeeds] of them.
void recurringFuzz() {
  final today = DateTime.utc(2026, 10, 15);
  const accounts = [Account('bank', '銀行', AccountKind.bank, 20000)];
  final items = [
    Recurring(
      id: 'm',
      name: '月',
      amount: 100,
      day: 31,
      account: 'bank',
      category: '房租',
      start: DateTime.utc(2026, 1, 31),
      auto: true,
    ),
    Recurring(
      id: 'w',
      name: '週',
      amount: 50,
      day: 1,
      account: 'bank',
      category: '房租',
      unit: RepeatUnit.week,
      start: DateTime.utc(2026, 8, 3),
    ),
    Recurring(
      id: 'e3',
      name: '三月',
      amount: 70,
      day: 29,
      account: 'bank',
      category: '房租',
      every: 3,
      start: DateTime.utc(2026, 2, 28),
    ),
    Recurring(
      id: 'y',
      name: '年',
      amount: 70,
      day: 29,
      account: 'bank',
      category: '房租',
      unit: RepeatUnit.year,
      start: DateTime.utc(2024, 2, 29),
    ),
    Recurring(
      id: 'o',
      name: '舊',
      amount: 70,
      day: 31,
      account: 'bank',
      category: '房租',
    ),
  ];
  String snap(Ledger l) {
    final s = l.recurringService;
    final b = StringBuffer();
    for (final i in l.recurring.all) {
      b.writeln(
        '${i.id} pend ${s.pendingDate(i)} next ${s.nextDate(i)} '
        'settled ${s.settled(i).entries.map((e) => '${e.key}:${e.value.toIso8601String()}').toList()..sort()} '
        'unposted ${s.unpostedDates(i, from: DateTime.utc(2026, 1), to: DateTime.utc(2026, 12, 31)).map((d) => d.toIso8601String())}',
      );
    }
    b.writeln(
      'due ${s.due.map((e) => e.id)} up ${s.upcoming.map((e) => e.id)}',
    );
    return b.toString();
  }

  for (var seed = 0; seed < fuzzSeeds; seed++) {
    test('recurring answers agree with a fresh ledger ($seed)', () {
      final r = Random(seed);
      final ledger = Ledger(
        today: today,
        accounts: accounts,
        categories: const [],
        entries: const [],
        holdings: const [],
        budgets: const [],
        recurring: items,
      );
      Ledger fresh() => Ledger(
        today: today,
        accounts: accounts,
        categories: const [],
        entries: [...ledger.entries.all],
        entryPlaces: [
          for (final e in ledger.entries.all) ledger.entries.orderOf(e.id),
        ],
        holdings: const [],
        budgets: const [],
        recurring: ledger.recurring.all,
      );
      final trashed = <Entry>[];
      for (var step = 0; step < 50; step++) {
        final item =
            ledger.recurring.all[r.nextInt(ledger.recurring.all.length)];
        final all = ledger.entries.all
            .where((e) => e.recurring != null)
            .toList();
        final ids = idsOf(ledger);
        final before = restoreState(ledger);
        final reason = 'seed $seed step $step';
        try {
          switch (r.nextInt(9)) {
            case 0:
              ledger.recurringCommands.confirm(item);
            case 1:
              final days = ledger.recurringService.unpostedDates(
                item,
                from: DateTime.utc(2026, 1),
                to: today,
              );
              ledger.recurringCommands.bookDays(
                item,
                days.take(1 + r.nextInt(4)).toList(),
              );
            case 2 when all.isNotEmpty:
              final x = ledger.entryCommands.remove(
                all[r.nextInt(all.length)].id,
              );
              if (x != null) trashed.add(x);
            case 3 when trashed.isNotEmpty:
              final back = ledger.entryCommands.restore(
                trashed.removeAt(r.nextInt(trashed.length)),
              );
              if (!back) expect(restoreState(ledger), before, reason: reason);
            case 4 when item.skipped.isNotEmpty:
              ledger.recurringCommands.unskip(item, item.skipped.first);
            case 5 when all.isNotEmpty:
              final e = all[r.nextInt(all.length)];
              ledger.entryCommands.replace(
                Entry(
                  id: e.id,
                  date: DateTime.utc(2026, 7 + r.nextInt(4), 1 + r.nextInt(28)),
                  type: e.type,
                  amount: e.amount,
                  account: e.account,
                  category: e.category,
                  note: e.note,
                  recurring: e.recurring,
                  merchant: e.merchant,
                ),
              );
            case 6:
              ledger.recurringCommands.bookDue();
            case 7 when ledger.trash.all.isNotEmpty:
              final t = ledger.trash.all[r.nextInt(ledger.trash.all.length)];
              final back = ledger.entryCommands.restoreTrashed(
                t,
                reopen: r.nextBool(),
                withOriginal: r.nextBool(),
              );
              if (!back) expect(restoreState(ledger), before, reason: reason);
            case 8 when all.length > 2:
              final x = ledger.entryCommands.removeAll([
                for (var i = 0; i < 3; i++) all[r.nextInt(all.length)].id,
              ]);
              if (r.nextBool()) {
                ledger.entryCommands.restoreAll(x);
              } else {
                trashed.addAll(x);
              }
          }
        } on RecordRefused {
          // refused
        }
        expectPartition(ledger, ids, reason);
        if (r.nextBool()) snap(ledger);
        expect(snap(ledger), snap(fresh()), reason: 'seed $seed step $step');
      }
    });
  }
}
