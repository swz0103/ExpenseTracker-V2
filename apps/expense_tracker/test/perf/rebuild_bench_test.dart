import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/places.dart';

/// What a screen costs when the book changes: a frame after a change the
/// screen does not show (a budget, on 總覽) against a frame after nothing,
/// medians of nine, with 20,000 entries more than the demo book. Slow, so
/// it only runs when asked: `BENCH=1 flutter test test/perf/rebuild_bench_test.dart`.
void main() {
  final asked = Platform.environment['BENCH'] != null;
  testWidgets('a frame after an unrelated change, on 總覽', (tester) async {
    final ledger = demoLedger();
    final r = Random(2);
    final today = ledger.today;
    ledger.entryCommands.addAll([
      for (var i = 0; i < 20000; i++)
        Entry(
          id: 'bench$i',
          date: today.subtract(Duration(days: r.nextInt(900))),
          type: EntryType.expense,
          amount: 10 + r.nextInt(900),
          account: ledger.accounts.main,
          category: ledger.categories.forEntries(income: false).first.name,
          merchant: '店${r.nextInt(80)}',
        ),
    ]);
    await show(tester, 360, 1, height: 800, book: ledger);
    await tester.pumpAndSettle();
    Future<double> median(void Function() change) async {
      final times = <int>[];
      for (var i = 0; i < 9; i++) {
        change();
        final watch = Stopwatch()..start();
        await tester.pump();
        times.add(watch.elapsedMicroseconds);
      }
      times.sort();
      return times[4] / 1000;
    }

    var limit = 1000;
    final idle = await median(() {});
    final budget = await median(
      () => ledger.budgetCommands.setBudget(allSpending, limit += 100),
    );
    final entry = await median(
      () => ledger.entryCommands.add(
        Entry(
          id: 'x${limit++}',
          date: today,
          type: EntryType.expense,
          amount: 50,
          account: ledger.accounts.main,
          category: ledger.categories.forEntries(income: false).first.name,
        ),
      ),
    );
    final shown = await median(ledger.amounts.toggle);
    // ignore: avoid_print
    print('frame: amounts hidden or shown ${shown.toStringAsFixed(2)} ms');
    // ignore: avoid_print
    print(
      'frame: idle ${idle.toStringAsFixed(2)} ms, '
      'after a budget ${budget.toStringAsFixed(2)} ms, '
      'after an entry ${entry.toStringAsFixed(2)} ms',
    );
  }, skip: !asked);
}
