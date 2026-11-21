import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/debts/model/debts.dart';
import 'package:flutter_test/flutter_test.dart';

/// What is owed either way, from balances alone.
void main() {
  const loan = Account(
    'car',
    '車貸',
    AccountKind.loan,
    -100000,
    principal: 120000,
  );
  const unknown = Account('old', '舊貸款', AccountKind.loan, -5000);
  const paidOff = Account('done', '還清', AccountKind.loan, 0, principal: 1);
  const friend = Account('amy', 'Amy', AccountKind.receivable, 500);
  const owing = Account('ben', 'Ben', AccountKind.receivable, -300);

  final balances = Ledger(
    today: DateTime.utc(2026, 10, 4),
    accounts: const [loan, unknown, paidOff, friend, owing],
    categories: const [],
    entries: const [],
    holdings: const [],
    budgets: const [],
    recurring: const [],
  ).balanceService;

  test('what a person owes, or nothing when it is the other way', () {
    expect(owedFrom(balances, friend), 500);
    expect(owedFrom(balances, owing), 0);
  });

  test('what is left on a loan, and how much of it is paid', () {
    expect(owedOn(balances, loan), 100000);
    expect(paidShare(balances, loan), closeTo(20000 / 120000, 1e-9));
    expect(paidShare(balances, paidOff), 1.0);
    expect(paidShare(balances, unknown), isNull, reason: 'no amount taken out');
  });
}
