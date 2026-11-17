import 'dart:math';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/overview/ui/sections/assets_section.dart';
import 'package:expense_tracker/src/features/overview/ui/sections/daily_section.dart';
import 'package:expense_tracker/src/features/overview/ui/sections/flow_section.dart';
import 'package:expense_tracker/src/features/overview/ui/sections/market_section.dart';
import 'package:expense_tracker/src/features/overview/ui/sections/plan_section.dart';
import 'package:expense_tracker/src/features/overview/ui/sections/summary_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'places.dart';

/// Each block of 總覽 listens only to the topics it shows. One that
/// shows something it does not listen to is left stale by a change, so
/// after every random change each block of a page kept open must read
/// exactly as on a page opened afresh on the same book.
void main() {
  const sections = {
    'summary': SummarySection,
    'assets': AssetsSection,
    'plan': PlanSection,
    'market': MarketSection,
    'daily': DailySection,
    'flow': FlowSection,
  };

  /// Every word each block shows, in order.
  Map<String, List<String>> words(WidgetTester tester) => {
    for (final MapEntry(:key, :value) in sections.entries)
      key: [
        for (final w in tester.widgetList<RichText>(
          find.descendant(
            of: find.byType(value),
            matching: find.byType(RichText),
          ),
        ))
          w.text.toPlainText(),
      ],
  };

  for (final seed in [1, 2, 3]) {
    testWidgets('a block kept open reads as one opened afresh ($seed)', (
      tester,
    ) async {
      final r = Random(seed);
      final ledger = demoLedger();
      await show(tester, 360, 1, book: ledger);
      await tester.pumpAndSettle();
      expect(words(tester).values.where((w) => w.isNotEmpty), hasLength(6));
      var serial = 0;
      final today = ledger.today;
      for (var step = 0; step < 24; step++) {
        final what = r.nextInt(9);
        final spending = ledger.categories.forEntries(income: false);
        switch (what) {
          case 0:
            ledger.entryCommands.add(
              Entry(
                id: 'fresh${serial++}',
                date: today.subtract(Duration(days: r.nextInt(5))),
                type: r.nextBool() ? EntryType.expense : EntryType.income,
                amount: 50 + r.nextInt(5000),
                account: ledger.accounts.main,
                category: spending[r.nextInt(spending.length)].name,
              ),
            );
          case 1:
            ledger.budgetCommands.setBudget(
              r.nextBool() ? allSpending : spending.first.name,
              1000 + r.nextInt(30000),
            );
          case 2 when ledger.budgets.all.isNotEmpty:
            ledger.budgetCommands.removeBudget(
              ledger.budgets.all.first.category,
            );
          case 3 when ledger.recurring.all.isNotEmpty:
            final item =
                ledger.recurring.all[r.nextInt(ledger.recurring.all.length)];
            ledger.recurringCommands.saveRecurring(
              item.copyWith(amount: item.amount + 100),
            );
          case 4:
            final a =
                ledger.accounts.all[r.nextInt(ledger.accounts.all.length)];
            ledger.accountCommands.updateAccount(
              a.copyWith(name: '${a.name}*', opening: a.opening + 1000),
            );
          case 5:
            final c = spending[r.nextInt(spending.length)];
            ledger.categoryCommands.updateCategory(
              c.name,
              c.copyWith(name: '${c.name}${serial++}'),
            );
          case 6:
            // Fresh closes for the stocks held, at a new price.
            final quotes = [
              for (final h in ledger.holdings.all)
                Holding(
                  h.code,
                  h.name,
                  shares: 0,
                  price: h.price + r.nextInt(20) - 10,
                  cost: 0,
                  change: 0,
                ),
            ];
            ledger.holdingCommands.setMarket(
              holdings: quotes,
              moves: {for (final h in quotes) h.code: r.nextInt(20) - 10.0},
              rates: {'USD': 30.0 + r.nextInt(3)},
              quotedOn: today,
            );
          case 7:
            ledger.amounts.toggle();
          case 8 when ledger.entries.onDay(today).isNotEmpty:
            ledger.entryCommands.remove(ledger.entries.onDay(today).first.id);
        }
        await tester.pumpAndSettle();
        final kept = words(tester);
        await show(tester, 360, 1, book: ledger);
        await tester.pumpAndSettle();
        expect(kept, words(tester), reason: 'step $step, change $what');
      }
    });
  }
}
