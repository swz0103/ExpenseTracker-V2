import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ledger's own work at scale, without the store: the median of
/// several runs of each question after a change, so one slow run on a
/// busy machine does not decide it. Slow, so it only runs when asked:
/// `BENCH=1 flutter test test/perf/memory_bench_test.dart`.
void main() {
  final asked = Platform.environment['BENCH'] != null;
  final today = DateTime.utc(2026, 10, 4);
  const names = ['居家', '飲食', '交通', '購物', '訂閱', '其他'];

  Ledger make(int count) {
    final r = Random(1);
    return Ledger(
      today: today,
      accounts: [
        for (var i = 0; i < 6; i++)
          Account('a$i', '帳戶$i', AccountKind.bank, 100000),
        const Account(
          'card',
          '卡',
          AccountKind.card,
          0,
          closingDay: 20,
          dueDay: 5,
        ),
      ],
      categories: const [],
      entries: [
        for (var i = 0; i < count; i++)
          Entry(
            id: 'e$i',
            date: today.subtract(Duration(days: r.nextInt(365 * 5))),
            type: r.nextInt(8) == 0 ? EntryType.income : EntryType.expense,
            amount: 30 + r.nextInt(2000),
            account: r.nextInt(5) == 0 ? 'card' : 'a${r.nextInt(6)}',
            category: names[r.nextInt(names.length)],
            merchant: '店${r.nextInt(300)}',
            installments: r.nextInt(50) == 0 ? 6 : 1,
          ),
      ],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
  }

  /// The median, in ms, of [runs] runs of [body] each after [before].
  double median(int runs, void Function() before, void Function() body) {
    final times = <int>[];
    for (var i = 0; i < runs; i++) {
      before();
      final watch = Stopwatch()..start();
      body();
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    return times[runs ~/ 2] / 1000;
  }

  test(
    'what a change costs the screens, by question',
    () {
      final ledger = make(100000);
      var n = 0;
      void change() => ledger.entryCommands.add(
        Entry(
          id: 'x${n++}',
          date: today,
          type: EntryType.expense,
          amount: 100,
          account: 'a0',
          category: '飲食',
        ),
      );
      final rows = {
        'balance': () => ledger.balanceService.balance('a0'),
        'card due': () =>
            ledger.statementService.statementDue(ledger.account('card')),
        'month': () => ledger.reportService.expense(2026, 10),
        'net worth': () => ledger.balanceService.netWorthAt(today),
        'search': () => ledger.entryQueryService.search('店12'),
        'usual': () => ledger.entryQueryService.usual(),
        'year spending': () =>
            ledger.reportService.spendingBetween(DateTime.utc(2026), today),
        'merchant stats': () => ledger.reportService.merchantStats,
        'add': change,
      };
      for (final MapEntry(:key, :value) in rows.entries) {
        final ms = median(9, key == 'add' ? () {} : change, value);
        // ignore: avoid_print
        print('${key.padRight(16)}${ms.toStringAsFixed(2).padLeft(9)} ms');
      }
    },
    skip: asked ? false : 'BENCH=1 to run',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
