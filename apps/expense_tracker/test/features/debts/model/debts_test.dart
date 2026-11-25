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

  test('the people and loans in all are summed at home, never cents as '
      'NT\$', () {
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 4),
      accounts: const [
        Account('ming', '小明', AccountKind.receivable, 500),
        Account('amy', '小美', AccountKind.receivable, 10000, currency: 'USD'),
        Account('owe', '阿欠', AccountKind.receivable, -200),
        Account('loan', '房貸', AccountKind.loan, -100000),
        Account('uloan', '美元貸', AccountKind.loan, -1000, currency: 'USD'),
      ],
      categories: const [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      rates: const {'USD': 32},
    );
    final all = ledger.accounts.all;
    // 500 + US$100 x 32 = 3700; 阿欠 owes nothing.
    expect(
      owedFromAll(ledger.balanceService, [
        for (final a in all)
          if (a.kind == AccountKind.receivable) a,
      ]),
      3700,
    );
    // 100000 + US$10 x 32 = 100320.
    expect(
      owedOnAll(ledger.balanceService, [
        for (final a in all)
          if (a.kind == AccountKind.loan) a,
      ]),
      100320,
    );
  });

  test('review 40: people are ranked and summed in NT\$, a person in US\$ '
      'by their worth at home, not their cents', () {
    final ledger = Ledger(
      today: DateTime.utc(2026, 10, 4),
      accounts: const [
        Account('ming', '小明', AccountKind.receivable, 5000),
        Account('amy', '小美', AccountKind.receivable, 10000, currency: 'USD'),
        Account('gone', '已封存', AccountKind.receivable, 900, archived: true),
        Account('loan', '房貸', AccountKind.loan, -100000),
      ],
      categories: const [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      rates: const {'USD': 32},
    );
    // 小美: US\$100 x 32 = 3,200 at home, below 小明's 5,000, though her
    // 10,000 cents are more.
    expect(
      [
        for (final a in peopleOwing(ledger.accounts, ledger.balanceService))
          a.id,
      ],
      ['ming', 'amy'],
    );
    // 5,000 + 3,200 = 8,200; the archived person is not open.
    expect(owedByPeople(ledger.accounts, ledger.balanceService), 8200);
    expect([for (final a in openLoans(ledger.accounts)) a.id], ['loan']);
    expect(daysSince(ledger.today, DateTime.utc(2026, 10, 1)), 3);
    expect(daysSince(ledger.today, DateTime.utc(2026, 10, 9)), 0);
  });
}
