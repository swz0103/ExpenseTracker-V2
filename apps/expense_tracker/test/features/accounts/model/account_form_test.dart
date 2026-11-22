import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/accounts/model/account_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing.
final class _Nowhere implements LedgerDataSource {
  @override
  Future<void> keep(WriteBatch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  Ledger book() => Ledger(
    today: DateTime.utc(2026, 10, 4),
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 5000),
      Account('card', '卡', AccountKind.card, -1200, closingDay: 25, dueDay: 10),
    ],
    categories: [],
    entries: const [],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    dataSource: _Nowhere(),
  );

  group('ACC-05: a credit limit is read with the one parser', () {
    AccountForm card(String limit) => AccountForm(book())
      ..kind = AccountKind.card
      ..name = '卡'
      ..limit = limit;

    test('80,000 and 80000.0 are 80,000', () {
      expect(card('80,000').build().limit, 80000);
      expect(card('80000.0').build().limit, 80000);
      expect(card('80,000').limitProblem, isNull);
    });
    test('left empty, there is no limit and nothing is wrong', () {
      expect(card('').build().limit, isNull);
      expect(card('').limitProblem, isNull);
      expect(card('').problem, isNull);
    });
    test('what is not a limit is said so, and is not saved as none', () {
      final form = card('8萬');
      expect(form.limitProblem, '不是有效的金額');
      expect(form.problem, '不是有效的金額');
      expect(form.save(), isFalse);
      expect(card('80000.5').limitProblem, '小數位數比這個幣別多');
    });
  });

  test('a new account needs a name and opens at the balance typed', () {
    final ledger = book();
    final form = AccountForm(ledger);
    expect(form.save(), isFalse);
    expect(form.problem, isNotNull);
    form
      ..name = ' 郵局 '
      ..balance = '3,000'
      ..currency = 'USD';
    expect(form.save(), isTrue);
    final made = ledger.accounts.all.last;
    expect(made.name, '郵局');
    expect(made.currency, 'USD');
    expect(ledger.balanceService.balance(made.id), 300000);
  });

  test('a card is kept in NT\$ and its balance typed as what is owed', () {
    final ledger = book();
    final form = AccountForm(ledger, old: ledger.account('card'));
    expect(form.balance, '1200');
    expect(form.foreignAllowed, isFalse);
    form
      ..balance = '800'
      ..closing = 5
      ..limit = '50000';
    expect(form.save(), isTrue);
    final card = ledger.account('card');
    expect(ledger.balanceService.balance('card'), -800);
    expect((card.closingDay, card.limit), (5, 50000));
  });

  test('an empty balance leaves the balance as it is', () {
    final ledger = book();
    final form = AccountForm(ledger, old: ledger.account('bank'))
      ..balance = ''
      ..name = '薪轉';
    expect(form.save(), isTrue);
    expect(ledger.balanceService.balance('bank'), 5000);
    expect(ledger.account('bank').name, '薪轉');
  });

  test('settling moves what is left, or pays what is owed', () {
    final ledger = book();
    final left = AccountForm.settlement(ledger, ledger.account('bank'), 'x');
    expect((left.account, left.to, left.amount), ('bank', 'x', 5000));
    final owed = AccountForm.settlement(ledger, ledger.account('card'), 'bank');
    expect((owed.account, owed.to, owed.amount), ('bank', 'card', 1200));
  });

  test(
    'a new account comes after the placed ones; a change keeps its place',
    () {
      final ledger = book();
      ledger.accountCommands.placeAccounts(['card', 'bank']);
      expect(ledger.account('card').place, 0);
      final form = AccountForm(ledger)..name = '郵局';
      expect(form.save(), isTrue);
      expect(ledger.accounts.all.last.place, 2);
      final edit = AccountForm(ledger, old: ledger.account('bank'))
        ..name = '薪轉';
      expect(edit.save(), isTrue);
      expect(ledger.account('bank').place, 1);
    },
  );

  test(
    'a loan keeps what was borrowed, and its money can go into an account',
    () {
      final ledger = book();
      final form = AccountForm(ledger)
        ..kind = AccountKind.loan
        ..name = '車貸'
        ..principal = '350,000'
        ..balance = '300,000'
        ..fundInto = 'bank';
      expect(form.save(), isTrue);
      final loan = ledger.accounts.all.last;
      expect(loan.principal, 350000);
      expect(loan.place, isNull);
      expect(ledger.balanceService.balance(loan.id), -300000);
      expect(ledger.balanceService.balance('bank'), 305000);
      final plain = AccountForm(ledger)
        ..kind = AccountKind.loan
        ..name = '信貸'
        ..balance = '50,000';
      expect(plain.save(), isTrue);
      expect(
        ledger.balanceService.balance(ledger.accounts.all.last.id),
        -50000,
      );
      expect(ledger.accounts.all.last.principal, isNull);
      expect(ledger.balanceService.balance('bank'), 305000);
    },
  );

  test('a loan keeps its terms, and owes its amount when nothing else is '
      'typed', () {
    final ledger = book();
    final form = AccountForm(ledger)
      ..kind = AccountKind.loan
      ..name = '房貸'
      ..principal = '1,000,000'
      ..rate = '2'
      ..months = '240'
      ..repay = LoanRepay.even
      ..due = 10
      ..payFrom = 'bank';
    expect(form.plan?.first, 5059);
    expect(form.save(), isTrue);
    final loan = ledger.accounts.all.last;
    expect(ledger.balanceService.balance(loan.id), -1000000);
    expect(
      (
        loan.loan?.rate,
        loan.loan?.months,
        loan.loan?.repay,
        loan.dueDay,
        loan.loan?.payFrom,
      ),
      (200, 240, LoanRepay.even, 10, 'bank'),
    );
    final again = AccountForm(ledger, old: loan);
    expect((again.rate, again.months), ('2', '240'));
  });

  test('a picked colour is kept, and none keeps the kind\'s', () {
    final ledger = book();
    final form = AccountForm(ledger)
      ..name = '旅費'
      ..color = 0xFF8E7CC0;
    expect(form.save(), isTrue);
    expect(ledger.accounts.all.last.color, 0xFF8E7CC0);
    final edit = AccountForm(ledger, old: ledger.accounts.all.last)
      ..color = null;
    expect(edit.save(), isTrue);
    expect(ledger.accounts.all.last.color, isNull);
  });
}
