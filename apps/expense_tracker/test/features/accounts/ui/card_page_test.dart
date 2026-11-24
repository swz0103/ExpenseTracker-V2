/// Checks how a card's page is read out.
library;

import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:expense_tracker/src/core/widgets/pickers.dart';
import 'package:expense_tracker/src/features/accounts/ui/card_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester tester, Ledger ledger) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: CardPage(
          ledger: ledger,
          accountId: 'card',
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
}

List<(String?, String?)> _bars(WidgetTester tester) => [
  for (final w in tester.widgetList<LinearProgressIndicator>(
    find.byType(LinearProgressIndicator),
  ))
    (w.semanticsLabel, w.semanticsValue),
];

void main() {
  testWidgets('F21: a bar is read as words and a percent, not a bare '
      'number first', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 10),
      accounts: const [
        Account(
          'card',
          '卡',
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
          date: DateTime.utc(2026, 10, 1),
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
    await _show(tester, ledger);
    // 25,000 of a 100,000 limit is 25% taken; the cycle from Sep 26 to
    // Oct 25 is 15 of 30 days gone, 50%.
    expect(_bars(tester), containsAll([('本期已過', '50%'), ('額度已用', '25%')]));
    handle.dispose();
  });

  testWidgets('R26: a closing day 31 card after a 30 November close counts '
      'the cycle to 31 December', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    final ledger = Ledger(
      today: DateTime.utc(2026, 12, 5),
      accounts: const [
        Account(
          'card',
          '卡',
          AccountKind.card,
          0,
          closingDay: 31,
          dueDay: 15,
          limit: 100000,
        ),
      ],
      categories: [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    await _show(tester, ledger);
    // Closed Nov 30 (no 31st), next close Dec 31: 31 days, 5 gone on
    // Dec 5; 5 / 31 = 16.1%, read as 16%.
    expect(find.textContaining('第 5 / 31 天'), findsOneWidget);
    expect(_bars(tester), contains(('本期已過', '16%')));
    handle.dispose();
  });

  testWidgets('an instalment plan\'s bar is read as 分期已繳 and a percent '
      '(review 16: progress semantics, instalments)', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 10),
      accounts: const [
        Account(
          'card',
          '卡',
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
          id: 'tv',
          date: DateTime.utc(2026, 7, 1),
          type: EntryType.expense,
          amount: 12000,
          account: 'card',
          category: '購物',
          installments: 12,
        ),
      ],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    await _show(tester, ledger);
    // Bought Jul 1 on a card closing on the 25th: billed on the Jul, Aug
    // and Sep statements, 3 of 12 periods, 25%.
    expect(find.textContaining('第 3 / 12 期'), findsOneWidget);
    expect(_bars(tester), contains(('分期已繳', '25%')));
  });

  testWidgets('R28: two closes moved apart count the cycle to the later '
      'one, and moving the close starts from it', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = Ledger(
      today: DateTime.utc(2027, 3, 1),
      accounts: [
        Account(
          'card',
          '卡',
          AccountKind.card,
          0,
          closingDay: 15,
          dueDay: 5,
          limit: 100000,
          closes: {
            DateTime.utc(2027, 2, 15): DateTime.utc(2027, 2, 8),
            DateTime.utc(2027, 3, 15): DateTime.utc(2027, 3, 22),
          },
        ),
      ],
      categories: [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    await _show(tester, ledger);
    // Closed 8 Feb (moved from the 15th), next close 22 Mar (moved from
    // the 15th): 28 + 14 = 42 days, 21 gone on 1 Mar.
    expect(find.textContaining('第 21 / 42 天'), findsOneWidget);
    await tester.tap(find.byKey(Keys.moveClose));
    await tester.pumpAndSettle();
    final picker = tester.widget<DayChoices>(find.byType(DayChoices));
    expect(picker.selected, DateTime.utc(2027, 3, 22));
    // At most a week after the scheduled 15 Mar: 22 Mar.
    expect(picker.latest, DateTime.utc(2027, 3, 22));
    expect(picker.marked, {DateTime.utc(2027, 3, 15)});
  });
}
