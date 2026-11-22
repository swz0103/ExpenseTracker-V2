import 'package:ledger_loans/calc/loan_plan.dart';
import 'package:test/test.dart';

void main() {
  test('the same each month: a million at 2% over 20 years', () {
    final plan = loanPlan(
      amount: 1000000,
      rate: 200,
      months: 240,
      repay: LoanRepay.even,
    )!;
    // r = 0.02 / 12; payment = 1000000 r / (1 - (1 + r)^-240) = 5058.83
    // -> 5059. Interest = 5058.83 x 240 - 1000000 = 214,120.0.
    expect(plan.first, 5059);
    expect(plan.last, 5059);
    expect(plan.interest, 214120);
  });

  test('the same share of the loan: less each month', () {
    final plan = loanPlan(
      amount: 1200000,
      rate: 300,
      months: 120,
      repay: LoanRepay.principal,
    )!;
    // Share 1200000 / 120 = 10,000; first interest 1200000 x 0.0025 =
    // 3,000; last 10000 x 0.0025 = 25.
    expect(plan.first, 13000);
    expect(plan.last, 10025);
    // 3000 x 121 / 2 = 181,500.
    expect(plan.interest, 181500);
  });

  test('interest only: the loan at the end', () {
    final plan = loanPlan(
      amount: 600000,
      rate: 240,
      months: 12,
      repay: LoanRepay.interest,
    )!;
    // 600000 x 0.024 / 12 = 1,200 a month; x 12 = 14,400.
    expect((plan.first, plan.last, plan.interest), (1200, 601200, 14400));
  });

  test('interest only: the months add up to the exact interest', () {
    final plan = loanPlan(
      amount: 1000000,
      rate: 200,
      months: 240,
      repay: LoanRepay.interest,
    )!;
    // A month is 1000000 x 0.02 / 12 = 1666.67 -> 1,667.
    expect(plan.first, 1667);
    // 240 months: 1000000 x 0.02 x 20 = 400,000 exactly (not 1667 x 240
    // = 400,080).
    expect(plan.interest, 400000);
    // 239 months: 398,333.33 -> 398,333; the last month's interest is
    // 400,000 - 398,333 = 1,667, paid with the loan: 1,001,667.
    expect(plan.last, 1001667);
  });

  test('interest only: the last month takes what rounding left over', () {
    final plan = loanPlan(
      amount: 10000,
      rate: 100,
      months: 3,
      repay: LoanRepay.interest,
    )!;
    // A month is 10000 x 0.01 / 12 = 8.33 -> 8. Three months: 25 exactly.
    // Two months 16.67 -> 17, so the last month pays 25 - 17 = 8 with the
    // loan: 10,008. 8 + 9 + 8 = 25.
    expect((plan.first, plan.last, plan.interest), (8, 10008, 25));
  });

  test('no interest, and nothing to work out while fields are missing', () {
    expect(loanPlan(amount: 1200, rate: 0, months: 12, repay: LoanRepay.even), (
      first: 100,
      last: 100,
      interest: 0,
    ));
    expect(
      loanPlan(amount: 1200, rate: null, months: 12, repay: LoanRepay.interest),
      (first: 0, last: 1200, interest: 0),
    );
    expect(
      loanPlan(amount: null, rate: 200, months: 12, repay: LoanRepay.even),
      isNull,
    );
    expect(
      loanPlan(amount: 1000, rate: 200, months: 0, repay: LoanRepay.even),
      isNull,
    );
  });
}
