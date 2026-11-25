/// Checks what 更多 says about this month.
library;

import 'package:expense_tracker/src/app/more_page.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';

void main() {
  testWidgets('RPT-06: the savings rate is rounded as everywhere, not cut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = ledgerOf(
      today: day(2026, 10, 20),
      categories: [Category('飲食', 'food', 0xFF5C9A83)],
      entries: [
        entryOf('i', day(2026, 10, 1), EntryType.income, 1000, 'bank'),
        entryOf('e', day(2026, 10, 2), EntryType.expense, 991, 'bank'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: MorePage(
            ledger: ledger,
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
    // (1,000 - 991) / 1,000 = 0.9%: 1%, as the report rounds it; this
    // page once cut it to 0%.
    expect(find.text('結餘率 1%'), findsOneWidget);
  });

  testWidgets('review 40: 代墊與借貸 says what people owe in NT\$, as its '
      'page does', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = Ledger(
      today: day(2026, 10, 20),
      accounts: const [
        Account('amy', '小美', AccountKind.receivable, 10000, currency: 'USD'),
      ],
      categories: const [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      rates: const {'USD': 32},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: MorePage(
            ledger: ledger,
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
    // US\$100.00 at 32 = 3,200; the tile once added the 10,000 cents.
    expect(find.text('欠你 3,200'), findsOneWidget);
    expect(find.text('欠你 10,000'), findsNothing);
  });
}
