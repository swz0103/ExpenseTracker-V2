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

  testWidgets('a stock sold out shows what the sale brought in, net of fee '
      'and tax (1.3-3)', (tester) async {
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
          fee: 171,
          account: 'bank',
          category: investmentCategory,
          holding: '2330',
          shares: 1000,
        ),
        Entry(
          id: 's',
          date: DateTime.utc(2026, 10, 8),
          type: EntryType.sell,
          amount: 130000,
          fee: 185,
          tax: 390,
          account: 'bank',
          category: investmentCategory,
          holding: '2330',
          shares: 1000,
        ),
      ],
      holdings: const [
        Holding('2330', '台積電', shares: 0, price: 130, cost: 0, change: 0),
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
    expect(find.text('已賣光'), findsWidgets);
    // Received 130,000 - 185 - 390 = 129,425; paid 120,000 + 171 =
    // 120,171; made 129,425 - 120,171 = +9,254.
    expect(find.text('賣出 129,425 · 買進 120,171'), findsOneWidget);
    expect(find.text('+9,254'), findsOneWidget);
  });

  testWidgets('a capital reduction is listed as 減資 with the shares taken '
      'and the cash returned (review 16)', (tester) async {
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
          date: DateTime.utc(2026, 9, 1),
          type: EntryType.buy,
          amount: 50000,
          account: 'bank',
          category: investmentCategory,
          holding: '1101',
          shares: 1000,
        ),
        Entry(
          id: 'cut',
          date: DateTime.utc(2026, 10, 8),
          type: EntryType.dividend,
          amount: 3000,
          account: 'bank',
          category: dividendCategory,
          holding: '1101',
          shares: -300,
        ),
      ],
      holdings: const [
        Holding('1101', '台泥', shares: 0, price: 50, cost: 0, change: 0),
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
            code: '1101',
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
    // 1,000 bought, 300 taken back: 700 held, at the 50,000 paid less
    // the 3,000 returned.
    expect(find.text('700 股 · 成本 47,000'), findsOneWidget);
    expect(find.textContaining('減資', findRichText: true), findsOneWidget);
    // 300 shares taken back, 3,000 returned to the account.
    expect(find.text('300 股'), findsOneWidget);
    expect(find.text('+3,000'), findsOneWidget);
  });
}
