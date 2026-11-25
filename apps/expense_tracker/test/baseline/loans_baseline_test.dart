// Loan plans (first and last payment, total interest) and how a loan
// stands in the balances. Hand arithmetic is beside each figure.
import 'package:ledger_loans/calc/loan_plan.dart';
import 'package:ledger_loans/model/rate.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/debts/model/debts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'baseline_ledger.dart';

LoanPlan plan(int amount, int rate, int months, LoanRepay repay) =>
    loanPlan(amount: amount, rate: rate, months: months, repay: repay)!;

void main() {
  group('1,000,000 at 2.00% a year over 240 months', () {
    // Decision D4: an exact schedule, each month's interest (what is owed
    // x 0.02 / 12) rounded half up to the NT\$ on its own.
    test('equal payments: 5,059 a month, the last 5,010, 214,111 interest', () {
      // r = 0.02/12; payment = P r / (1 - (1+r)^-240) = 5058.83 -> 5059.
      // First month: interest 1000000 r = 1666.67 -> 1667, so 3392 off.
      // After 239 payments 5,002 is still owed; the last month pays it
      // with its interest 5002 r = 8.34 -> 8: 5,010.
      // Interest = 5059 x 239 + 5010 - 1000000 = 214,111.
      final p = plan(1000000, 200, 240, LoanRepay.even);
      expect(p.first, 5059);
      expect(p.last, 5010);
      expect(p.interest, 214111);
    });
    test('equal principal: first 5,833, last 4,333, interest 200,867', () {
      // Share = 1000000 ~/ 240 = 4166; the 160 left over (1000000 -
      // 4166 x 240) goes with the last month, which pays down 4326.
      // First = 4166 + 1000000 r (1666.67 -> 1667) = 5833.
      // Last = 4326 + 4326 r (7.21 -> 7) = 4333.
      // Interest = the 240 months' rounded interest added up = 200,867.
      final p = plan(1000000, 200, 240, LoanRepay.principal);
      expect(p.first, 5833);
      expect(p.last, 4333);
      expect(p.interest, 200867);
    });
    test('interest only: 1,667 a month, the principal with the last', () {
      // 1000000 x 0.02 / 12 = 1666.67 -> 1667 a month.
      // The months add up to the exact interest, 1000000 x 0.02 x 20 =
      // 400,000 (finding F72 / PKG-04: not the rounded payment x 240).
      final p = plan(1000000, 200, 240, LoanRepay.interest);
      expect(p.first, 1667);
      expect(p.last, 1001667);
      expect(p.interest, 400000);
    });
  });

  group('smaller loans', () {
    test('12,000 at 12% over 12 months, equal payments', () {
      // r = 0.01; payment = 120 / (1 - 1.01^-12) = 1066.19 -> 1066.
      // Each month's interest is 1% of what is owed, rounded: 120 + 111 +
      // 101 + 91 + 82 + 72 + 62 + 52 + 42 + 31 + 21 + 11 = 796; the last
      // month pays the 1,059 left with its interest 11: 1,070.
      final p = plan(12000, 1200, 12, LoanRepay.even);
      expect(p.first, 1066);
      expect(p.last, 1070);
      expect(p.interest, 796);
    });
    test('12,000 at 12% over 12 months, equal principal', () {
      // Share 1000. First = 1000 + 12000 x 0.01 = 1120.
      // Last = 1000 + 1000 x 0.01 = 1010.
      // Interest = 12000 x 0.01 x 13 / 2 = 780.
      final p = plan(12000, 1200, 12, LoanRepay.principal);
      expect(p.first, 1120);
      expect(p.last, 1010);
      expect(p.interest, 780);
    });
    test('a loan at no interest pays the same share each month', () {
      // 120000 / 12 = 10000, no interest.
      final even = plan(120000, 0, 12, LoanRepay.even);
      expect((even.first, even.last, even.interest), (10000, 10000, 0));
      // 100000 / 3 = 33333.3 -> 33333; the last month takes the 33,334
      // that is left.
      expect(plan(100000, 0, 3, LoanRepay.even).first, 33333);
      expect(plan(100000, 0, 3, LoanRepay.even).last, 33334);
    });
    test('a missing rate is read as no interest', () {
      final p = loanPlan(
        amount: 120000,
        rate: null,
        months: 12,
        repay: LoanRepay.even,
      )!;
      expect(p.first, 10000);
    });
    test('no plan while the amount or the months are missing', () {
      expect(
        loanPlan(amount: null, rate: 200, months: 12, repay: LoanRepay.even),
        isNull,
      );
      expect(
        loanPlan(amount: 0, rate: 200, months: 12, repay: LoanRepay.even),
        isNull,
      );
      expect(
        loanPlan(amount: 1000, rate: 200, months: 0, repay: LoanRepay.even),
        isNull,
      );
      expect(
        loanPlan(amount: 1000, rate: 200, months: null, repay: LoanRepay.even),
        isNull,
      );
    });
  });

  group('rates as typed, in hundredths of a percent', () {
    test('typed text becomes hundredths', () {
      expect(rateOf('2.15'), 215);
      expect(rateOf('2'), 200);
      expect(rateOf('.5'), 50);
      expect(rateOf(' 3.1 '), 310);
      expect(rateOf('100'), 10000);
    });
    test('digits past two places round half up, as written', () {
      // 1.005 -> 1.00 plus the next digit 5 -> 1.01 -> 101 (not a double).
      expect(rateOf('1.005'), 101);
      // 1.004 -> next digit 4 -> stays 1.00.
      expect(rateOf('1.004'), 100);
    });
    test('anything else is no rate', () {
      expect(rateOf('abc'), isNull);
      expect(rateOf(''), isNull);
      expect(rateOf('100.01'), isNull);
      expect(rateOf('-1'), isNull);
    });
    test('a rate is shown back as typed', () {
      expect(rateText(215), '2.15');
      expect(rateText(200), '2');
      expect(rateText(250), '2.5');
      expect(rateText(205), '2.05');
      expect(rateText(null), '');
    });
  });

  group('a loan in the balances', () {
    Ledger book() => ledgerOf(
      today: day(2026, 10, 25),
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 500000),
        Account(
          'mortgage',
          '房貸',
          AccountKind.loan,
          -1000000,
          principal: 1000000,
        ),
      ],
    );

    test('a fresh loan is a debt of its principal', () {
      final ledger = book();
      final loan = ledger.account('mortgage');
      expect(owedOn(ledger.balanceService, loan), 1000000);
      expect(paidShare(ledger.balanceService, loan), 0.0);
      expect(ledger.balanceService.loanDebt, 1000000);
    });
    test('net worth is what is held less what is owed', () {
      final ledger = book();
      // Assets 500000 (bank); the loan -1000000 counted against them;
      // net worth = 500000 - 1000000 = -500000.
      expect(ledger.balanceService.assets, 500000);
      expect(ledger.balanceService.netWorthAt(day(2026, 10, 25)), -500000);
    });
    test('paying 12,000 into the loan moves money, not net worth', () {
      final ledger = book();
      ledger.entryCommands.add(
        entryOf(
          'pay',
          day(2026, 10, 25),
          EntryType.transfer,
          12000,
          'bank',
          to: 'mortgage',
        ),
      );
      // Bank 500000 - 12000 = 488000; loan -1000000 + 12000 = -988000.
      expect(ledger.balanceService.balance('bank'), 488000);
      expect(ledger.balanceService.balance('mortgage'), -988000);
      // Net worth is the same: 488000 - 988000 = -500000.
      expect(ledger.balanceService.netWorthAt(day(2026, 10, 25)), -500000);
    });
    test('a loan with no amount given has no paid share', () {
      final ledger = ledgerOf(
        today: day(2026, 10, 25),
        accounts: const [Account('l', '借款', AccountKind.loan, -5000)],
      );
      expect(paidShare(ledger.balanceService, ledger.account('l')), isNull);
      expect(owedOn(ledger.balanceService, ledger.account('l')), 5000);
    });
  });
}
