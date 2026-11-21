/// Checks the loan's form: what was borrowed, its rate, months and day
/// typed on its card are the loan kept, with the account it is paid from;
/// money paid out into an account is recorded as owed from the start.
library;

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/formatting/words.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/accounts/forms/account_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

void main() {
  late Ledger ledger;
  setUp(() => ledger = demoLedger());

  /// Opens the loan's form, for [loan] when given.
  Future<void> open(WidgetTester tester, {Account? loan}) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editLoan(context, ledger, loan: loan),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String digits) async {
    for (final key in ['C', ...digits.split(''), Words.done]) {
      await tester.tap(find.byKey(Keys.calc(key)));
      await tester.pumpAndSettle();
    }
  }

  /// The account added since [before] accounts were in the book.
  Account added(int before) => ledger.accounts.all.skip(before).single;

  testWidgets('a new loan keeps its terms and is paid out into an account', (
    tester,
  ) async {
    final count = ledger.accounts.all.length;
    final bank = ledger.balanceService.balance('bank');
    await open(tester);
    expect(find.text('新增貸款'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '學貸');
    await go(tester, ['借了多少']);
    await type(tester, '300000');
    await go(tester, ['年利率', '2.5%', '期數', '5 年', '每月扣款']);
    await go(tester, ['10', '本金平均', '從哪扣款', '日常銀行', '撥款到', '^日常銀行']);
    expect(find.bySemanticsLabel(RegExp('從哪扣款，日常銀行')), findsOneWidget);
    expect(find.bySemanticsLabel('年利率 2.5%'), findsOneWidget);
    expect(find.bySemanticsLabel('期數 60 期'), findsOneWidget);
    await go(tester, ['儲存']);

    final loan = added(count);
    expect(
      (loan.name, loan.kind, loan.principal, loan.dueDay),
      ('學貸', AccountKind.loan, 300000, 10),
    );
    final terms = loan.loan!;
    expect(
      (terms.months, terms.repay, terms.payFrom),
      (60, LoanRepay.principal, 'bank'),
    );
    expect(terms.rate, isNotNull);
    // The money paid out is owed, and now in the bank.
    expect(ledger.balanceService.balance(loan.id), -300000);
    expect(ledger.balanceService.balance('bank'), bank + 300000);
  });

  testWidgets('a loan paid out nowhere is owed from the start all the same', (
    tester,
  ) async {
    final count = ledger.accounts.all.length;
    await open(tester);
    await tester.enterText(find.byType(TextField).first, '信貸');
    await go(tester, ['借了多少']);
    await type(tester, '100000');
    await go(tester, ['期數', '2 年', '只繳息', '儲存']);
    final loan = added(count);
    expect((loan.loan!.months, loan.loan!.repay), (24, LoanRepay.interest));
    expect(ledger.balanceService.balance(loan.id), -100000);
  });

  testWidgets('a panel closed with 取消 leaves the rate as it was', (
    tester,
  ) async {
    await open(tester);
    await go(tester, ['年利率', Words.cancel]);
    expect(find.bySemanticsLabel('年利率 —'), findsOneWidget);
  });

  testWidgets('a rate typed in 其他 and kept with 完成 is the loan\'s rate', (
    tester,
  ) async {
    await open(tester);
    await go(tester, ['年利率']);
    await tester.enterText(find.byType(TextField).last, '1.85');
    await go(tester, [Words.done]);
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('年利率 1.85%'), findsOneWidget);
  });

  testWidgets('a loan changed keeps what is owed as typed', (tester) async {
    final loan = ledger.accounts.all.firstWhere(
      (a) => a.kind == AccountKind.loan,
    );
    await open(tester, loan: loan);
    expect(find.text('編輯貸款'), findsOneWidget);
    await go(tester, ['目前尚欠']);
    await type(tester, '12345');
    await go(tester, ['從哪扣款', '不指定', '儲存']);
    expect(ledger.balanceService.balance(loan.id), -12345);
    expect(ledger.account(loan.id).loan?.payFrom, isNull);
  });
}
