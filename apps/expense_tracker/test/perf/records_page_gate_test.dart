import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';
import '../support/places.dart';

/// 收支紀錄 costs what is on screen, not what the month holds: on a book
/// of 100,000 entries more than the demo book, spread over three years
/// (about 2,800 a month), 隱藏金額 and a save build again about as many
/// widgets as on the demo book alone (counted, so the same on every
/// machine), and the first letter searched for after a save takes about
/// as long (the least of [gateTries] runs, as a ratio).
///
/// Before (review 10): 3,572 widgets on 隱藏金額 against 577, a day of
/// entries being one card built whole; the search's text was worked out
/// again from every entry after any change. With `BENCH=1` the figures
/// are printed.
void main() {
  final bench = Platform.environment['BENCH'] != null;

  /// The demo book with [size] entries more, as the page bench makes it.
  Ledger book(int size) {
    final ledger = demoLedger();
    if (size == 0) return ledger;
    final r = Random(3);
    final today = ledger.today;
    final spend = [
      for (final c in ledger.categories.forEntries(income: false)) c.name,
    ];
    final accounts = [
      for (final a in ledger.accounts.all)
        if (!a.kind.isDebt) a.id,
    ];
    ledger.entryCommands.addAll([
      for (var i = 0; i < size; i++)
        Entry(
          id: 'b$i',
          date: today.subtract(Duration(days: (size - i) * 1095 ~/ size)),
          type: EntryType.expense,
          amount: 40 + i * 37 % 900,
          account: accounts[i % accounts.length],
          category: spend[i % spend.length],
          merchant: '店${r.nextInt(300)}',
          note: i.isEven ? '午餐' : '',
        ),
    ]);
    return ledger;
  }

  Future<int> built(WidgetTester tester, void Function() change) async {
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

  var serial = 0;
  void save(Ledger ledger) => ledger.entryCommands.add(
    Entry(
      id: 'gate${serial++}',
      date: ledger.today,
      type: EntryType.expense,
      amount: 50,
      account: ledger.accounts.main,
      category: ledger.categories.forEntries(income: false).first.name,
      note: '午餐',
    ),
  );

  Future<void> type(WidgetTester tester, String words) async {
    await tester.enterText(find.byType(TextField).first, words);
    // The search waits for a pause in typing.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  /// Widgets built again on 隱藏金額 and on a save, and the least time of
  /// the first letter searched for after a save, on 紀錄 with [size]
  /// entries more than the demo book.
  Future<Map<String, int>> measure(WidgetTester tester, int size) async {
    final ledger = book(size);
    await show(tester, 360, 1, height: 800, book: ledger);
    await go(tester, ['紀錄']);
    final toggle = await built(tester, ledger.amounts.toggle);
    await built(tester, ledger.amounts.toggle);
    final saved = await built(tester, () => save(ledger));
    // What a search keeps: worked out once, before the saves.
    await type(tester, '午');
    await type(tester, '');
    final search = await leastOf(gateTries, () async {
      save(ledger);
      await tester.pumpAndSettle();
      final watch = Stopwatch()..start();
      await type(tester, '午');
      final us = watch.elapsedMicroseconds;
      await type(tester, '');
      return us;
    });
    // The undo note's timer.
    await tester.pumpAndSettle(const Duration(seconds: 10));
    return {'toggle': toggle, 'save': saved, 'search': search};
  }

  testWidgets('紀錄 builds and searches as much at 100,000 entries', (
    tester,
  ) async {
    // Warm up the code paths first, so the small book is not charged for
    // compiling them.
    await measure(tester, 0);
    final small = await measure(tester, 0);
    final large = await measure(tester, 100000);
    if (bench) {
      // ignore: avoid_print
      print('demo book: $small; 100,000 more: $large');
    }
    for (final what in ['toggle', 'save']) {
      expect(
        large[what]! / small[what]!,
        lessThanOrEqualTo(1.5),
        reason:
            'after $what, ${small[what]} widgets built on the demo book, '
            '${large[what]} with 100,000 entries: the page builds what '
            'the month holds',
      );
    }
    // A floor of 5 ms keeps a tiny figure from deciding.
    expect(
      large['search']! / max(small['search']!, 5000),
      lessThanOrEqualTo(2),
      reason:
          'the first letter after a save took ${small['search']} µs on '
          'the demo book, ${large['search']} µs with 100,000 entries: '
          'the search works out what it kept again',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
