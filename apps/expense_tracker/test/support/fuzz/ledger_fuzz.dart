import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fuzz.dart';

final today = DateTime.utc(2026, 10, 15);
const accounts = [
  Account('cash', '現金', AccountKind.cash, 5000),
  Account('bank', '銀行', AccountKind.bank, 20000),
  Account('c1', '卡1', AccountKind.card, 0, closingDay: 10, dueDay: 25),
  Account('c2', '卡2', AccountKind.card, 0, closingDay: 20, dueDay: 5),
];

Ledger fresh(Ledger l) => Ledger(
  today: today,
  accounts: accounts,
  categories: const [],
  entries: [...l.entries.all],
  entryPlaces: [for (final e in l.entries.all) l.entries.orderOf(e.id)],
  holdings: const [],
  budgets: const [],
  recurring: const [],
);

String snap(Ledger l) {
  final b = StringBuffer();
  for (final a in accounts) {
    b.writeln(
      '${a.id} bal ${l.balanceService.balance(a.id)}'
      ' ${l.balanceService.balance(a.id, until: DateTime.utc(2026, 8, 31))}'
      ' ${l.balanceService.balance(a.id, until: DateTime.utc(2026, 12, 31))}',
    );
    b.writeln(
      ' entriesOf ${l.balanceService.entriesOf(a.id).map((e) => e.id).join(',')}',
    );
    for (final m in [8, 9, 10, 11]) {
      b.writeln(
        ' flow$m ${l.balanceService.flowOf(a.id, DateTime.utc(2026, m))}',
      );
    }
    if (a.kind == AccountKind.card) {
      final s = l.statementService;
      b.writeln(
        ' st ${s.statement(a)} due ${s.statementDue(a)}'
        ' unb ${s.unbilled(a).map((e) => e.id).join(',')}'
        ' inst ${s.instalmentsOn(a).map((e) => e.id).join(',')}',
      );
    }
  }
  for (final m in [8, 9, 10, 11]) {
    b.writeln(
      'rep$m ${l.reportService.income(2026, m)} ${l.reportService.expense(2026, m)}'
      ' ${l.entries.inMonth(2026, m).map((e) => e.id).join(',')}',
    );
  }
  for (final w in ['a', 'x', 'e1', '1']) {
    b.writeln(
      'search $w ${l.entryQueryService.search(w).map((e) => e.id).join(',')}',
    );
  }
  return b.toString();
}

/// Seeded runs, [fuzzSeeds] of them.
void ledgerFuzz() {
  for (var seed = 0; seed < fuzzSeeds; seed++) {
    test('ledger caches agree with a fresh ledger ($seed)', () {
      final r = Random(seed);
      var n = 0;
      Entry make({String? id, bool refundable = true}) {
        final kind = r.nextInt(6);
        final acct = ['cash', 'bank', 'c1', 'c2'][r.nextInt(4)];
        final isCard =
            acct.startsWith('c') && acct.length == 2 && acct != 'cash';
        return Entry(
          id: id ?? 'e${n++}',
          date: DateTime.utc(2026, 8 + r.nextInt(4), 1 + r.nextInt(28)),
          type: kind == 0
              ? EntryType.income
              : kind == 1
              ? EntryType.transfer
              : EntryType.expense,
          amount: 100 + r.nextInt(900),
          account: acct,
          to: kind == 1 ? ['cash', 'bank', 'c1', 'c2'][r.nextInt(4)] : null,
          category: kind == 0 ? '薪資' : '飲食',
          note: r.nextBool() ? 'note a$n' : 'x',
          installments: kind >= 4 && isCard ? 3 + r.nextInt(3) : 0,
        );
      }

      final ledger = Ledger(
        today: today,
        accounts: accounts,
        categories: const [],
        entries: const [],
        holdings: const [],
        budgets: const [],
        recurring: const [],
      );
      final removed = <Entry>[];
      void guard(void Function() f) {
        try {
          f();
        } on RecordRefused {
          // refused
        }
      }

      for (var step = 0; step < 60; step++) {
        final all = ledger.entries.all;
        switch (r.nextInt(9)) {
          case 0 || 1 || 2:
            guard(() => ledger.entryCommands.add(make()));
          case 3 when all.isNotEmpty:
            final e = all[r.nextInt(all.length)];
            guard(() => ledger.entryCommands.replace(make(id: e.id)));
          case 4 when all.isNotEmpty:
            final e = all[r.nextInt(all.length)];
            final x = ledger.entryCommands.remove(e.id);
            if (x != null) removed.add(x);
          case 5 when removed.isNotEmpty:
            final e = removed.removeAt(r.nextInt(removed.length));
            ledger.entryCommands.restore(e);
          case 6 when all.length > 3:
            final ids = [
              for (var i = 0; i < 3; i++) all[r.nextInt(all.length)].id,
            ];
            final x = ledger.entryCommands.removeAll(ids);
            if (x.isNotEmpty && r.nextBool()) {
              ledger.entryCommands.restoreAll(x);
            } else {
              removed.addAll(x);
            }
          case 7 when all.isNotEmpty:
            final e = all[r.nextInt(all.length)];
            // a refund of an existing entry
            guard(
              () => ledger.entryCommands.add(
                Entry(
                  id: 'e${n++}',
                  date: DateTime.utc(2026, 9 + r.nextInt(2), 1 + r.nextInt(28)),
                  type: EntryType.income,
                  amount: 10 + r.nextInt(50),
                  account: e.account,
                  category: e.category,
                  refundOf: e.id,
                ),
              ),
            );
          case 8 when ledger.trash.all.isNotEmpty:
            final t = ledger.trash.all[r.nextInt(ledger.trash.all.length)];
            ledger.entryCommands.restoreTrashed(t);
        }
        if (r.nextInt(3) == 0) {
          // read some, so lazily absorbed things are partly settled
          snap(ledger);
        }
        if (r.nextInt(4) == 0 || step == 59) {
          expect(
            snap(ledger),
            snap(fresh(ledger)),
            reason: 'seed $seed step $step',
          );
        }
      }
    });
  }
}
