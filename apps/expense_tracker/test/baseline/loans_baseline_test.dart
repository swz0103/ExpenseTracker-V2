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
    test('equal payments: 5,059 a month, 214,120 interest', () {
      // r = 0.02/12 = 0.0016667; payment = P r / (1 - (1+r)^-240) = 5058.9.
      // 5058.9 rounds to 5059; interest = 5058.9 x 240 - 1000000 = 214,120.
      final p = plan(1000000, 200, 240, LoanRepay.even);
      expect(p.first, 5059);
      expect(p.last, 5059);
      expect(p.interest, 214120);
    });
    test('equal principal: first 5,833, last 4,174, interest 200,833', () {
      // Share = 1000000 / 240 = 4166.67. First = 4166.67 + 1000000 r = 5833.3.
      // Last = 4166.67 + 4166.67 r = 4173.6 -> 4174.
      // Interest = P r (n + 1) / 2 = 1666.67 x 241 / 2 = 200,833.3.
      final p = plan(1000000, 200, 240, LoanRepay.principal);
      expect(p.first, 5833);
      expect(p.last, 4174);
      expect(p.interest, 200833);
    });
    test('interest only: 1,667 a month, the principal with the last', () {
      // 1000000 x 0.02 / 12 = 1666.67 -> 1667 a month.
      // The total interest is left out on purpose: the code gives 400,080
      // (the rounded payment x 240) where the exact figure is 400,000.
      // That is finding F72 / PKG-04, not behaviour to keep.
      final p = plan(1000000, 200, 240, LoanRepay.interest);
      expect(p.first, 1667);
      expect(p.last, 1001667);
    });
  });

  group('smaller loans', () {
    test('12,000 at 12% over 12 months, equal payments', () {
      // r = 0.01; payment = 120 / (1 - 1.01^-12) = 1066.19 -> 1066.
      // Interest = 1066.19 x 12 - 12000 = 794.3 -> 794.
      final p = plan(12000, 1200, 12, LoanRepay.even);
      expect(p.first, 1066);
      expect(p.interest, 794);
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
      // 100000 / 3 = 33333.3 -> 33333.
      expect(plan(100000, 0, 3, LoanRepay.even).first, 33333);
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
