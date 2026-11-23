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
    // -> 5,059 for 239 months. Each month's interest is rounded on its
    // own (the first: 1000000 x 0.02 / 12 = 1666.67 -> 1,667), so after
    // 239 months 5,002 is still owed; the last month pays it with its
    // interest 5002 x 0.02 / 12 = 8.34 -> 8: 5,010.
    expect(plan.first, 5059);
    expect(plan.last, 5010);
    // All that is paid less the loan: 5059 x 239 + 5010 - 1000000.
    expect(plan.interest, 214111);
  });

  test('the same each month: every month of 12,000 at 12% over a year', () {
    final schedule = loanSchedule(
      amount: 12000,
      rate: 1200,
      months: 12,
      repay: LoanRepay.even,
    )!;
    // 1% a month; payment = 120 / (1 - 1.01^-12) = 1066.19 -> 1,066.
    // Interest is 1% of what is owed, rounded: 120.00, 110.54 -> 111,
    // 100.99 -> 101, ...; the last month pays the 1,059 left and its
    // interest 10.59 -> 11.
    expect(schedule, const [
      (payment: 1066, interest: 120, principal: 946, balance: 11054),
      (payment: 1066, interest: 111, principal: 955, balance: 10099),
      (payment: 1066, interest: 101, principal: 965, balance: 9134),
      (payment: 1066, interest: 91, principal: 975, balance: 8159),
      (payment: 1066, interest: 82, principal: 984, balance: 7175),
      (payment: 1066, interest: 72, principal: 994, balance: 6181),
      (payment: 1066, interest: 62, principal: 1004, balance: 5177),
      (payment: 1066, interest: 52, principal: 1014, balance: 4163),
      (payment: 1066, interest: 42, principal: 1024, balance: 3139),
      (payment: 1066, interest: 31, principal: 1035, balance: 2104),
      (payment: 1066, interest: 21, principal: 1045, balance: 1059),
      (payment: 1070, interest: 11, principal: 1059, balance: 0),
    ]);
    // 120 + 111 + 101 + 91 + 82 + 72 + 62 + 52 + 42 + 31 + 21 + 11 = 796.
    expect(
      loanPlan(amount: 12000, rate: 1200, months: 12, repay: LoanRepay.even),
      (first: 1066, last: 1070, interest: 796),
    );
  });

  test('the same each month: a few NT\$ over many months end early', () {
    final schedule = loanSchedule(
      amount: 3,
      rate: 0,
      months: 4,
      repay: LoanRepay.even,
    )!;
    // 3 / 4 = 0.75 -> 1 a month: paid off in three, nothing in the last.
    expect(schedule.map((p) => p.payment), [1, 1, 1, 0]);
    expect(schedule.map((p) => p.balance), [2, 1, 0, 0]);
  });

  test('the same each month at no interest: the last takes the rest', () {
    final schedule = loanSchedule(
      amount: 100000,
      rate: 0,
      months: 3,
      repay: LoanRepay.even,
    )!;
    // 100000 / 3 = 33333.33 -> 33,333 twice; 33,334 is left for the last.
    expect(schedule.map((p) => p.payment), [33333, 33333, 33334]);
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
    // 3000 x 121 / 2 = 181,500 (every month's interest is whole).
    expect(plan.interest, 181500);
  });

  test('the same share of the loan: the last month takes the remainder', () {
    final schedule = loanSchedule(
      amount: 1000,
      rate: 1200,
      months: 3,
      repay: LoanRepay.principal,
    )!;
    // Share 1000 ~/ 3 = 333, the 1 left over with the last month: 334.
    // Interest at 1% a month: 10.00, 6.67 -> 7, 3.34 -> 3.
    expect(schedule, const [
      (payment: 343, interest: 10, principal: 333, balance: 667),
      (payment: 340, interest: 7, principal: 333, balance: 334),
      (payment: 337, interest: 3, principal: 334, balance: 0),
    ]);
  });

  test('interest is rounded half up, the one rounding of a loan', () {
    expect(loanInterestRounding, LoanRounding.halfUp);
    // 5 / 2 = 2.5 -> 3 half up, 2 dropped; 7 / 3 = 2.33 -> 2 either way.
    final (five, two, seven, three) = (
      BigInt.from(5),
      BigInt.two,
      BigInt.from(7),
      BigInt.from(3),
    );
    expect(roundedQuotient(five, two, LoanRounding.halfUp), BigInt.from(3));
    expect(roundedQuotient(five, two, LoanRounding.down), BigInt.two);
    expect(roundedQuotient(seven, three, LoanRounding.halfUp), BigInt.two);
    expect(roundedQuotient(seven, three, LoanRounding.down), BigInt.two);
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
    expect(
      loanSchedule(amount: 0, rate: 200, months: 12, repay: LoanRepay.even),
      isNull,
    );
  });
}
