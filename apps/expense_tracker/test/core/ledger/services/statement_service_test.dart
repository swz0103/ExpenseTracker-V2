import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart' show BillDue, BillDueToday;
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

  test('a 預定 purchase is not unbilled nor in instalments yet (D25)', () {
    // Today is 10/4; the purchases of 10/7 are 預定.
    final b = book([
      entry('c', account: 'card', amount: 400, date: DateTime.utc(2026, 10)),
      entry('p', account: 'card', amount: 700, date: DateTime.utc(2026, 10, 7)),
      entry(
        'tv',
        account: 'card',
        amount: 1200,
        installments: 3,
        date: DateTime.utc(2026, 10, 7),
      ),
    ]);
    expect(b.statements.unbilled(_card).map((e) => e.id), ['c']);
    expect(b.statements.instalmentsOn(_card), isEmpty);
    b.today = DateTime.utc(2026, 10, 7);
    expect(b.statements.unbilled(_card).map((e) => e.id), ['p', 'c']);
    expect(b.statements.instalmentsOn(_card).map((e) => e.id), ['tv']);
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

  test('a payment on the close day is in the statement; one the day after '
      'pays it (mutation review 11)', () {
    Entry pay(String id, int d) => entry(
      id,
      type: EntryType.transfer,
      amount: 400,
      to: 'card',
      date: DateTime.utc(2026, 9, d),
    );
    final spent = entry(
      'a',
      account: 'card',
      amount: 1000,
      date: DateTime.utc(2026, 9, 20),
    );
    // Paid on the close, 9/25: the statement closed owing 600.
    expect(book([spent, pay('p', 25)]).statements.statementDue(_card), 600);
    // Paid on 9/26: the statement closed owing 1,000, 400 paid since.
    expect(book([spent, pay('p', 26)]).statements.statementDue(_card), 600);
    // Both: 600 owed at the close, 400 paid since.
    expect(
      book([spent, pay('p', 25), pay('q', 26)]).statements.statementDue(_card),
      200,
    );
  });

  group('edges review 11 found untested', () {
    final spent = entry(
      'a',
      account: 'card',
      amount: 1000,
      date: DateTime.utc(2026, 9, 20),
    );

    test('a statement due on a day off can be paid the next business day', () {
      // Due Saturday 10/10 (國慶日): payable until Monday 10/12.
      final b = book([spent])..today = DateTime.utc(2026, 10, 11);
      expect(
        b.statements.billStatus(_card),
        BillDue(BusinessDate(2026, 10, 10), 1),
      );
      b.today = DateTime.utc(2026, 10, 12);
      expect(
        b.statements.billStatus(_card),
        BillDueToday(BusinessDate(2026, 10, 10)),
      );
    });

    test('on a close day the statement before is still the last', () {
      final b = book([spent])..today = DateTime.utc(2026, 10, 25);
      final (start, end, due) = b.statements.statement(_card);
      expect(
        (start, end, due),
        (
          DateTime.utc(2026, 8, 26),
          DateTime.utc(2026, 9, 25),
          DateTime.utc(2026, 10, 10),
        ),
      );
    });

    test('since the close: purchases of one payment, refunds and rewards; '
        'not the close day\'s, nor instalments of two', () {
      final b = book([
        entry(
          'closeDay',
          account: 'card',
          amount: 50,
          date: DateTime.utc(2026, 9, 25),
        ),
        entry(
          'after',
          account: 'card',
          amount: 70,
          date: DateTime.utc(2026, 9, 26),
        ),
        entry(
          'two',
          account: 'card',
          amount: 600,
          installments: 2,
          date: DateTime.utc(2026, 9, 27),
        ),
        entry(
          'reward',
          type: EntryType.income,
          account: 'card',
          amount: 30,
          date: DateTime.utc(2026, 9, 28),
        ),
      ]);
      // Newest first.
      expect(b.statements.unbilled(_card).map((e) => e.id), [
        'reward',
        'after',
      ]);
    });

    test('instalments all billed are no longer listed', () {
      final b = book([
        entry(
          'tv',
          account: 'card',
          amount: 1200,
          installments: 3,
          date: DateTime.utc(2026, 6, 1),
        ),
      ]);
      // Billed on 6/25, 7/25 and 8/25.
      expect(b.statements.instalmentsOn(_card), isEmpty);
    });

    test('a US\$ card is paid down by what arrived, in US cents', () {
      const usdCard = Account(
        'usdCard',
        '美元卡',
        AccountKind.card,
        0,
        closingDay: 25,
        dueDay: 10,
        currency: 'USD',
      );
      final b = Book(
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 100000),
          usdCard,
        ],
        entries: [
          entry(
            'a',
            account: 'usdCard',
            amount: 20000,
            date: DateTime.utc(2026, 9, 20),
          ),
          Entry(
            id: 'pay',
            date: DateTime.utc(2026, 10, 1),
            type: EntryType.transfer,
            amount: 3200,
            account: 'bank',
            to: 'usdCard',
            received: 10000,
          ),
        ],
      );
      // US\$200.00 billed, US\$100.00 arrived: US\$100.00 still due.
      expect(b.statements.statementDue(usdCard), 10000);
    });
  });
}
