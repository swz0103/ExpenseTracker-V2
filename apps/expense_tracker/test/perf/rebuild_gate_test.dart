import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/places.dart';

/// How much of 總覽 is built again after a change: counted, not timed, so
/// the same on every machine and every run, and kept by CI on each
/// change. A change that makes a screen build more than it did fails
/// here; one that makes it build less lowers the number. The time the
/// same frames take is measured on a phone (integration_test/bench_test)
/// and by `BENCH=1 flutter test test/perf/rebuild_bench_test.dart`.
void main() {
  /// The most widgets built again after each change, as measured.
  // An entry or the amounts shown build one more since 1.5: 總覽's notice
  // of bills to pay follows the book, and is an empty box while none is due.
  // A budget builds 79 since PERF (was 153): the page's title and month
  // follow the entries, not the whole ledger.
  const most = {'nothing': 0, 'a budget': 79, 'an entry': 876, 'amounts': 876};

  testWidgets('a change builds no more of 總覽 than it did', (tester) async {
    final ledger = demoLedger();
    await show(tester, 360, 1, height: 800, book: ledger);
    await tester.pumpAndSettle();

    Future<int> built(void Function() change) async {
      var count = 0;
      debugOnRebuildDirtyWidget = (_, _) => count++;
      try {
        change();
        await tester.pumpAndSettle();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      return count;
    }

    final found = {
      'nothing': await built(() {}),
      'a budget': await built(
        () => ledger.budgetCommands.setBudget(allSpending, 33333),
      ),
      'an entry': await built(
        () => ledger.entryCommands.add(
          Entry(
            id: 'gate',
            date: ledger.today,
            type: EntryType.expense,
            amount: 50,
            account: ledger.accounts.main,
            category: ledger.categories.forEntries(income: false).first.name,
          ),
        ),
      ),
      'amounts': await built(ledger.amounts.toggle),
    };
    for (final MapEntry(key: change, value: count) in found.entries) {
      final limit = most[change]!;
      expect(
        count,
        lessThanOrEqualTo(limit),
        reason: 'after $change, $count widgets built again; it was $limit',
      );
      expect(
        count,
        limit,
        reason: 'after $change, fewer now: lower its number to $count',
      );
    }
    // The undo note's timer.
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}
