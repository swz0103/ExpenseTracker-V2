import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/debts/model/loan_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same each month: a million at 2% over 20 years', () {
    final plan = loanPlan(
      amount: 1000000,
      rate: 200,
      months: 240,
      repay: LoanRepay.even,
    )!;
    expect(plan.first, 5059);
    expect(plan.last, plan.first);
    expect(plan.interest, closeTo(214140, 200));
  });

  test('the same share of the loan: less each month', () {
    final plan = loanPlan(
      amount: 1200000,
      rate: 300,
      months: 120,
      repay: LoanRepay.principal,
    )!;
    expect(plan.first, 10000 + 3000);
    expect(plan.last, 10025);
    expect(plan.interest, 181500);
  });

  test('interest only: the loan at the end', () {
    final plan = loanPlan(
      amount: 600000,
      rate: 240,
      months: 12,
      repay: LoanRepay.interest,
    )!;
    expect((plan.first, plan.last, plan.interest), (1200, 601200, 14400));
  });

  test('no interest, and nothing to work out while fields are missing', () {
    expect(loanPlan(amount: 1200, rate: 0, months: 12, repay: LoanRepay.even), (
      first: 100,
      last: 100,
      interest: 0,
    ));
    expect(
      loanPlan(amount: null, rate: 200, months: 12, repay: LoanRepay.even),
      isNull,
    );
    expect(
      loanPlan(amount: 1000, rate: 200, months: 0, repay: LoanRepay.even),
      isNull,
    );
  });

  test('rates as typed and shown', () {
    expect(rateOf('2.15'), 215);
    expect(rateOf(' 3 '), 300);
    expect(rateOf('abc'), isNull);
    expect(rateOf('120'), isNull);
    expect(rateText(215), '2.15');
    expect(rateText(205), '2.05');
    expect(rateText(210), '2.1');
    expect(rateText(300), '3');
    expect(rateText(null), '');
  });
}
