import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/formatting/words.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/accounts/forms/reconcile_sheet.dart';
import 'package:expense_tracker/src/features/accounts/model/reconcile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

void main() {
  late Ledger ledger;
  late Account account;
  setUp(() {
    ledger = demoLedger();
    account = ledger.accounts.all.firstWhere((a) => a.kind == AccountKind.bank);
  });

  /// Opens 對帳 and types [counted] on the calculator.
  Future<void> count(WidgetTester tester, int counted) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => reconcileAccount(context, ledger, account),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Keys.calc('C')));
    for (final digit in '$counted'.split('')) {
      await tester.tap(find.byKey(Keys.calc(digit)));
    }
    await tester.tap(find.byKey(Keys.calc(Words.done)));
    await tester.pumpAndSettle();
  }

  testWidgets('more counted than the book holds is recorded as income, '
      'once agreed', (tester) async {
    final book = shownBalance(ledger.balanceService, account);
    final count0 = ledger.entries.length;
    await count(tester, book + 120);
    expect(find.textContaining('差 120'), findsOneWidget);
    await go(tester, ['記下']);

    expect(ledger.entries.length, count0 + 1);
    final added = ledger.entries.all.last;
    expect(
      (added.type, added.amount, added.account),
      (EntryType.income, 120, account.id),
    );
    expect(shownBalance(ledger.balanceService, account), book + 120);
    expect(find.text('已記下對帳調整 +120'), findsOneWidget);
  });

  testWidgets('less counted is recorded as spending', (tester) async {
    final book = shownBalance(ledger.balanceService, account);
    await count(tester, book - 35);
    await go(tester, ['記下']);
    expect(ledger.entries.all.last.type, EntryType.expense);
    expect(shownBalance(ledger.balanceService, account), book - 35);
  });

  testWidgets('declining records nothing', (tester) async {
    final count0 = ledger.entries.length;
    await count(tester, shownBalance(ledger.balanceService, account) + 5);
    await go(tester, [Words.cancel]);
    expect(ledger.entries.length, count0);
  });

  testWidgets('the same amount needs no adjustment', (tester) async {
    final count0 = ledger.entries.length;
    await count(tester, shownBalance(ledger.balanceService, account));
    expect(find.text('帳上金額一致，不用調整'), findsOneWidget);
    expect(ledger.entries.length, count0);
  });

  testWidgets('an overdrawn account starts the calculator blank (1.1-6)', (
    tester,
  ) async {
    // Spend 500 more than the account holds, today: its balance is −500.
    final held = shownBalance(ledger.balanceService, account);
    ledger.entryCommands.add(
      Entry(
        id: ledger.newId(),
        date: ledger.today,
        type: EntryType.expense,
        amount: held + 500,
        account: account.id,
        category: '飲食日常',
      ),
    );
    expect(shownBalance(ledger.balanceService, account), -500);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => reconcileAccount(context, ledger, account),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Not cleared first: 8 typed is 8, not −5008 or 5008.
    await tester.tap(find.byKey(Keys.calc('8')));
    await tester.tap(find.byKey(Keys.calc(Words.done)));
    await tester.pumpAndSettle();
    // 8 − (−500) = 508 more than the book.
    expect(find.textContaining('帳上 -500，實際 8，差 508'), findsOneWidget);
  });
}
