import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/accounts/model/account_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing.
final class _Nowhere implements Journal {
  @override
  Future<void> keep(Batch batch) async {}

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
    categories: const [],
    entries: const [],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    journal: _Nowhere(),
  );

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
    final made = ledger.accounts.last;
    expect(made.name, '郵局');
    expect(made.currency, 'USD');
    expect(ledger.balance(made.id), 300000);
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
    expect(ledger.balance('card'), -800);
    expect((card.closingDay, card.limit), (5, 50000));
  });

  test('an empty balance leaves the balance as it is', () {
    final ledger = book();
    final form = AccountForm(ledger, old: ledger.account('bank'))
      ..balance = ''
      ..name = '薪轉';
    expect(form.save(), isTrue);
    expect(ledger.balance('bank'), 5000);
    expect(ledger.account('bank').name, '薪轉');
  });

  test('settling moves what is left, or pays what is owed', () {
    final ledger = book();
    final left = AccountForm.settlement(ledger, ledger.account('bank'), 'x');
    expect((left.account, left.to, left.amount), ('bank', 'x', 5000));
    final owed = AccountForm.settlement(ledger, ledger.account('card'), 'bank');
    expect((owed.account, owed.to, owed.amount), ('bank', 'card', 1200));
  });
}
