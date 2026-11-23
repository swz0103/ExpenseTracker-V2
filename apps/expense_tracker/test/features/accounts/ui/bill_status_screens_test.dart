/// F19: an overdue card bill reads the same on the card's page, in the
/// account list and on 總覽.
library;

import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:expense_tracker/src/features/accounts/ui/account_card.dart';
import 'package:expense_tracker/src/features/accounts/ui/card_page.dart';
import 'package:expense_tracker/src/features/overview/ui/sections/card_due_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A card closing on the 25th, due on the 10th, with 25,000 spent on 9/20:
/// billed by the statement closing 9/25, due 10/10, and not paid.
Ledger _book(DateTime today) => Ledger(
  today: today,
  accounts: const [
    Account(
      'card',
      '日常卡',
      AccountKind.card,
      0,
      closingDay: 25,
      dueDay: 10,
      limit: 100000,
    ),
  ],
  categories: [],
  entries: [
    Entry(
      id: 'e',
      date: DateTime.utc(2026, 9, 20),
      type: EntryType.expense,
      amount: 25000,
      account: 'card',
      category: '飲食',
    ),
  ],
  holdings: const [],
  budgets: const [],
  recurring: const [],
);

final _nav = Nav(
  open: (_) {},
  back: () {},
  compose: ({type = EntryType.expense, entry, draft}) async {},
  showEntry: (_) {},
);

Future<void> _show(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  // 10/12 is two days after the due day 10/10.
  const overdue = '10/10 繳款 · 已逾期 2 天';
  final late = _book(DateTime.utc(2026, 10, 12));

  testWidgets('the card page says it is overdue', (tester) async {
    await _show(
      tester,
      SizedBox(
        height: 2400,
        child: CardPage(ledger: late, accountId: 'card', nav: _nav),
      ),
    );
    expect(find.text(overdue), findsOneWidget);
  });

  testWidgets('the account list says the same', (tester) async {
    await _show(
      tester,
      AccountCard(ledger: late, account: late.account('card')),
    );
    expect(find.text(overdue), findsOneWidget);
  });

  testWidgets('總覽 says the same', (tester) async {
    await _show(tester, CardDueSection(ledger: late, nav: _nav));
    expect(find.text('日常卡'), findsOneWidget);
    expect(find.text(overdue), findsOneWidget);
  });

  testWidgets('總覽 says nothing while the bill is not yet due', (tester) async {
    // 10/5 is five days before 10/10: due, not yet a reminder.
    await _show(
      tester,
      CardDueSection(ledger: _book(DateTime.utc(2026, 10, 5)), nav: _nav),
    );
    expect(find.text('日常卡'), findsNothing);
  });
}
