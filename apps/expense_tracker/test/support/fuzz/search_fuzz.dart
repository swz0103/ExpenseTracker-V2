import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fuzz.dart';

/// Seeded runs, [fuzzSeeds] of them.
void searchFuzz() {
  final today = DateTime.utc(2026, 10, 15);
  const accounts = [
    Account('cash', '現金', AccountKind.cash, 5000),
    Account('bank', '銀行', AccountKind.bank, 20000),
  ];
  const words = [
    'n',
    'no',
    'not',
    'note',
    'note 1',
    'note 12',
    '1',
    '12',
    '12a',
    'a',
    'ab',
    'ab1',
    'x',
    'X',
    '午',
    '午餐',
  ];
  for (var seed = 0; seed < fuzzSeeds; seed++) {
    test(
      'typing on, with edits between, finds what a fresh search finds ($seed)',
      () {
        final r = Random(seed);
        var n = 0;
        Entry make({String? id}) => Entry(
          id: id ?? 'e${n++}',
          date: DateTime.utc(2026, 8 + r.nextInt(3), 1 + r.nextInt(28)),
          type: EntryType.expense,
          amount: r.nextInt(3) == 0 ? 12 : 100 + r.nextInt(900),
          account: r.nextBool() ? 'cash' : 'bank',
          category: r.nextBool() ? '飲食' : '午餐',
          note: ['note 12', 'note 1', 'ab12a', 'Xa', '', 'not'][r.nextInt(6)],
          merchant: r.nextBool() ? '午餐店' : '',
          tags: r.nextBool() ? const ['ab1'] : const [],
        );
        final ledger = Ledger(
          today: today,
          accounts: accounts,
          categories: const [],
          entries: [for (var i = 0; i < 10; i++) make()],
          holdings: const [],
          budgets: const [],
          recurring: const [],
        );
        List<String> fresh(String w) {
          final f = Ledger(
            today: today,
            accounts: accounts,
            categories: const [],
            entries: [...ledger.entries.all],
            entryPlaces: [
              for (final e in ledger.entries.all) ledger.entries.orderOf(e.id),
            ],
            holdings: const [],
            budgets: const [],
            recurring: const [],
          );
          return [for (final e in f.entryQueryService.search(w)) e.id];
        }

        for (var step = 0; step < 80; step++) {
          final all = ledger.entries.all;
          switch (r.nextInt(6)) {
            case 0:
              ledger.entryCommands.add(make());
            case 1 when all.isNotEmpty:
              ledger.entryCommands.replace(
                make(id: all[r.nextInt(all.length)].id),
              );
            case 2 when all.isNotEmpty:
              ledger.entryCommands.remove(all[r.nextInt(all.length)].id);
            case 3:
              ledger.accountCommands.updateAccount(
                ledger.account('cash').copyWith(name: 'c${r.nextInt(9)}'),
              );
            case 4 when ledger.trash.all.isNotEmpty:
              ledger.entryCommands.restoreTrashed(ledger.trash.all.first);
            default:
          }
          for (var k = 0; k < 3; k++) {
            final w = words[r.nextInt(words.length)];
            expect(
              [for (final e in ledger.entryQueryService.search(w)) e.id],
              fresh(w),
              reason: 'seed $seed step $step "$w"',
            );
          }
        }
      },
    );
  }
}
