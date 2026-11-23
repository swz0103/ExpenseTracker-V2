/// Checks what a loan costs as its form shows it: the month's payment,
/// the last month when it differs, and the interest over the term.
library;

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/accounts/forms/loan_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_loans/calc/loan_plan.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    LoanRepay repay, {
    required int amount,
    required int rate,
    required int months,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: LoanEstimate(
          ledger: demoLedger(),
          plan: loanPlan(
            amount: amount,
            rate: rate,
            months: months,
            repay: repay,
          ),
          repay: repay,
          color: Colors.teal,
        ),
      ),
    ),
  );

  testWidgets('equal payments name the last month, which pays off the rest', (
    tester,
  ) async {
    // 1,000,000 at 2% over 240 months: 5,059 a month, the last 5,010,
    // 214,111 interest (test/baseline/loans_baseline_test.dart).
    await show(tester, LoanRepay.even, amount: 1000000, rate: 200, months: 240);
    expect(find.text('5,059'), findsOneWidget);
    expect(find.text('最後 5,010'), findsOneWidget);
    expect(find.text('214,111'), findsOneWidget);
  });

  testWidgets('equal payments that never differ name no last month', (
    tester,
  ) async {
    // 120,000 at no interest over 12 months: 10,000 every month.
    await show(tester, LoanRepay.even, amount: 120000, rate: 0, months: 12);
    expect(find.text('10,000'), findsOneWidget);
    expect(find.textContaining('最後'), findsNothing);
  });

  testWidgets('equal principal shows the first and the last month', (
    tester,
  ) async {
    // 1,000,000 at 2% over 240 months: first 5,833, last 4,333, 200,867
    // interest.
    await show(
      tester,
      LoanRepay.principal,
      amount: 1000000,
      rate: 200,
      months: 240,
    );
    expect(find.text('5,833'), findsOneWidget);
    expect(find.text('最後 4,333'), findsOneWidget);
    expect(find.text('200,867'), findsOneWidget);
  });
}
