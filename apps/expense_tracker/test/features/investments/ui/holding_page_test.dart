/// Checks how a holding's page writes its price.
library;

import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:expense_tracker/src/features/investments/ui/holding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('INV-03: a close of 128.5 is shown as 128.5, not 129', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 9),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 1000000)],
      categories: [],
      entries: [
        Entry(
          id: 'b',
          date: DateTime.utc(2026, 10, 1),
          type: EntryType.buy,
          amount: 120000,
          account: 'bank',
          category: investmentCategory,
          holding: '2330',
          shares: 1000,
        ),
      ],
      holdings: const [
        Holding('2330', '台積電', shares: 0, price: 128.5, cost: 0, change: 0),
      ],
      budgets: const [],
      recurring: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: HoldingPage(
            ledger: ledger,
            code: '2330',
            nav: Nav(
              open: (_) {},
              back: () {},
              compose: ({type = EntryType.expense, entry, draft}) async {},
              showEntry: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 128.5 is a real tick for prices of 100 to 500 (0.5 a step).
    expect(find.text('128.5'), findsWidgets);
    expect(find.text('129'), findsNothing);
  });
}
