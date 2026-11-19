import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';

const _card = Account(
  'card',
  '卡',
  AccountKind.card,
  0,
  closingDay: 25,
  dueDay: 10,
);

void main() {
  Book book(List<Entry> entries) => Book(
    accounts: const [Account('bank', '銀行', AccountKind.bank, 10000), _card],
    entries: entries,
  );

  test('a statement closing today is still open', () {
    final b = book(const []);
    expect(b.statements.closedBy, DateTime.utc(2026, 10, 3));
    final (start, end, due) = b.statements.statement(_card);
    expect(end, DateTime.utc(2026, 9, 25));
    expect(start, DateTime.utc(2026, 8, 26));
    expect(due, DateTime.utc(2026, 10, 10));
  });

  test('what is due is the closed spending less what was paid since', () {
    final b = book([
      entry('a', account: 'card', amount: 800, date: DateTime.utc(2026, 9, 20)),
      entry(
        'pay',
        type: EntryType.transfer,
        amount: 300,
        to: 'card',
        date: DateTime.utc(2026, 10, 1),
      ),
      entry(
        'later',
        account: 'card',
        amount: 99,
        date: DateTime.utc(2026, 10, 2),
      ),
    ]);
    expect(b.statements.statementDue(_card), 500);
    expect(b.statements.unbilled(_card).map((e) => e.id), ['later']);
  });

  test('an instalment purchase stays listed until every period is billed', () {
    final b = book([
      entry(
        'tv',
        account: 'card',
        amount: 1200,
        installments: 3,
        date: DateTime.utc(2026, 9, 1),
      ),
    ]);
    expect(b.statements.instalmentsOn(_card).map((e) => e.id), ['tv']);
    expect(b.statements.unbilled(_card), isEmpty);
    expect(b.statements.billedPeriods(b.entries.byId('tv')!, day), 1);
  });
}
