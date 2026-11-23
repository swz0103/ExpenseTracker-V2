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

/// A card closing on the 25th, due on the 15th, with 25,000 spent on 9/20:
/// billed by the statement closing 9/25, due Thursday 10/15 (a business
/// day, so not moved), and not paid.
Ledger _book(DateTime today, {int dueDay = 15}) => Ledger(
  today: today,
  accounts: [
    Account(
      'card',
      '日常卡',
      AccountKind.card,
      0,
      closingDay: 25,
      dueDay: dueDay,
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

/// 總覽's notice of bills to pay, as 總覽 builds it.
Widget _overview(Ledger ledger) => CardDueSection(
  changes: ledger,
  accounts: ledger.accounts,
  statements: ledger.statementService,
  nav: _nav,
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
  // 10/17 is two days after the due day 10/15.
  const overdue = '已逾期 2 天';
  final late = _book(DateTime.utc(2026, 10, 17));

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
    await _show(tester, _overview(late));
    expect(find.text('日常卡'), findsOneWidget);
    expect(find.text(overdue), findsOneWidget);
  });

  testWidgets('總覽 says nothing while the bill is not yet due', (tester) async {
    // 10/5 is ten days before 10/15: due, not yet a reminder.
    await _show(tester, _overview(_book(DateTime.utc(2026, 10, 5))));
    expect(find.text('日常卡'), findsNothing);
  });

  testWidgets('a due day on a holiday is not late until the business day '
      'after it', (tester) async {
    // Due on the 10th: 10/10/2026 is a Saturday and 國慶日, so the bill
    // can be paid on Monday 10/12. On 10/12 it is due today, not late.
    final book = _book(DateTime.utc(2026, 10, 12), dueDay: 10);
    await _show(tester, _overview(book));
    expect(find.text('今天繳款'), findsOneWidget);
    expect(find.textContaining('已逾期'), findsNothing);
  });

  testWidgets('the account list says when a moved due day can be paid', (
    tester,
  ) async {
    // 10/5: due Saturday 10/10, payable Monday 10/12.
    final book = _book(DateTime.utc(2026, 10, 5), dueDay: 10);
    await _show(
      tester,
      AccountCard(ledger: book, account: book.account('card')),
    );
    // 10/12 - 10/5 = 7 days to pay.
    expect(find.text('10/10 繳款 · 順延至 10/12 · 還有 7 天'), findsOneWidget);
  });

  group('D22: the days left read the same on the card page and the list', () {
    Widget page(Ledger book) => SizedBox(
      height: 2400,
      child: CardPage(ledger: book, accountId: 'card', nav: _nav),
    );
    Widget card(Ledger book) =>
        AccountCard(ledger: book, account: book.account('card'));

    testWidgets('due in ten days', (tester) async {
      // 10/15 - 10/5 = 10 days.
      final book = _book(DateTime.utc(2026, 10, 5));
      for (final shown in [page(book), card(book)]) {
        await _show(tester, shown);
        expect(find.text('10/15 繳款 · 還有 10 天'), findsOneWidget);
      }
    });

    testWidgets('due today', (tester) async {
      final book = _book(DateTime.utc(2026, 10, 15));
      for (final shown in [page(book), card(book), _overview(book)]) {
        await _show(tester, shown);
        expect(find.text('今天繳款'), findsOneWidget);
        expect(find.textContaining('還有'), findsNothing);
      }
    });

    testWidgets('postponed: counted to the day it can be paid', (tester) async {
      // Due Saturday 10/10 (國慶日), payable Monday 10/12: on 10/9 that is
      // 12 - 9 = 3 days, not the 1 day to 10/10.
      final book = _book(DateTime.utc(2026, 10, 9), dueDay: 10);
      for (final shown in [page(book), card(book)]) {
        await _show(tester, shown);
        expect(find.text('10/10 繳款 · 順延至 10/12 · 還有 3 天'), findsOneWidget);
      }
    });

    testWidgets('late: no days left, the days late', (tester) async {
      for (final shown in [page(late), card(late), _overview(late)]) {
        await _show(tester, shown);
        expect(find.text(overdue), findsOneWidget);
        expect(find.textContaining('還有'), findsNothing);
      }
    });
  });
}
