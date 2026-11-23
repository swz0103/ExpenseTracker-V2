import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/intents.dart';
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:test/test.dart';

import '../support/book.dart';

void main() {
  test('an opening balance against the opening equity', () {
    final b = book();
    expect(
      keep(
        b,
        OpeningBalance(
          id: const IntentId('o'),
          seq: 0,
          account: card,
          amount: -1200,
        ),
      ),
      isA<Written>(),
    );
    expect(linesOf(b, 'o'), [
      ('acct:card', -1200, 'TWD', 10101),
      ('equity:opening', 1200, 'TWD', 10101),
    ]);
  });

  test('a split spending, each part under its category', () {
    final b = book();
    keep(
      b,
      Spending(
        id: const IntentId('s'),
        date: day(9, 2),
        seq: 1,
        account: bank,
        parts: [(food, 600), (fees, 300)],
      ),
    );
    expect(linesOf(b, 's'), [
      ('acct:bank', -900, 'TWD', 20260902), // 600 + 300
      ('cat:spending:food', 600, 'TWD', 20260902),
      ('cat:spending:fees', 300, 'TWD', 20260902),
    ]);
  });

  test('income and a refund: the category is credited', () {
    final b = book();
    keep(
      b,
      Earning(
        id: const IntentId('pay'),
        date: day(9, 1),
        seq: 1,
        account: bank,
        category: salary,
        amount: 52000,
      ),
    );
    keep(
      b,
      Earning(
        id: const IntentId('back'),
        date: day(9, 9),
        seq: 2,
        account: card,
        category: food,
        amount: 1000,
      ),
    );
    expect(linesOf(b, 'pay'), [
      ('acct:bank', 52000, 'TWD', 20260901),
      ('cat:income:salary', -52000, 'TWD', 20260901),
    ]);
    // A refund lowers the spending of its category.
    expect(b.reader.month(day(9, 1)).spending, {food: -1000});
    expect(b.reader.month(day(9, 1)).income, {salary: 52000});
  });

  test('a transfer with the fee spent under the category kept with it', () {
    final b = book();
    keep(
      b,
      Transfer(
        id: const IntentId('t'),
        date: day(9, 3),
        seq: 1,
        from: bank,
        to: card,
        amount: 1000,
        fee: 15,
        feeCategory: fees,
      ),
    );
    expect(linesOf(b, 't'), [
      ('acct:bank', -1015, 'TWD', 20260903), // 1000 + 15
      ('acct:card', 1000, 'TWD', 20260903),
      ('cat:spending:fees', 15, 'TWD', 20260903),
    ]);
  });

  group('refused', () {
    RuleRejected refused(LedgerIntent i) =>
        book().journal.put(i) as RuleRejected;

    test('a money line on what is not a money account', () {
      final r = refused(
        Spending(
          id: const IntentId('s'),
          date: day(1, 1),
          seq: 1,
          account: food,
          parts: [(food, 1)],
        ),
      );
      expect((r.code, r.detail), ('notAMoneyAccount', 'cat:spending:food'));
      expect(
        refused(
          OpeningBalance(
            id: const IntentId('o'),
            seq: 0,
            account: food,
            amount: 1,
          ),
        ).code,
        'notAMoneyAccount',
      );
      expect(
        refused(
          Earning(
            id: const IntentId('e'),
            date: day(1, 1),
            seq: 1,
            account: food,
            category: salary,
            amount: 1,
          ),
        ).code,
        'notAMoneyAccount',
      );
      expect(
        refused(
          Transfer(
            id: const IntentId('t'),
            date: day(1, 1),
            seq: 1,
            from: food,
            to: bank,
            amount: 1,
          ),
        ).code,
        'notAMoneyAccount',
      );
      expect(
        refused(
          Transfer(
            id: const IntentId('t'),
            date: day(1, 1),
            seq: 1,
            from: bank,
            to: food,
            amount: 1,
          ),
        ).detail,
        'cat:spending:food',
      );
    });

    test('a negative amount, no parts, a fee with nowhere to go', () {
      expect(
        refused(
          Spending(
            id: const IntentId('s'),
            date: day(1, 1),
            seq: 1,
            account: bank,
            parts: [(food, -1)],
          ),
        ).code,
        'badAmount',
      );
      expect(
        refused(
          Spending(
            id: const IntentId('s'),
            date: day(1, 1),
            seq: 1,
            account: bank,
            parts: const [],
          ),
        ).code,
        'badAmount',
      );
      expect(
        refused(
          Earning(
            id: const IntentId('e'),
            date: day(1, 1),
            seq: 1,
            account: bank,
            category: salary,
            amount: -1,
          ),
        ).code,
        'badAmount',
      );
      expect(
        refused(
          Transfer(
            id: const IntentId('t'),
            date: day(1, 1),
            seq: 1,
            from: bank,
            to: card,
            amount: 5,
            fee: -1,
          ),
        ).code,
        'badAmount',
      );
      expect(
        refused(
          Transfer(
            id: const IntentId('t'),
            date: day(1, 1),
            seq: 1,
            from: bank,
            to: card,
            amount: 5,
            fee: 1,
          ),
        ).code,
        'noFeeCategory',
      );
    });
  });

  test('nothing at all posts nothing', () {
    final b = book();
    expect(
      keep(
        b,
        Spending(
          id: const IntentId('z'),
          date: day(1, 1),
          seq: 1,
          account: bank,
          parts: [(food, 0)],
        ),
      ),
      isA<Written>(),
    );
    expect(b.store.postingCount, 0);
    expect(Spending.kind.value, 'entries.spending');
    expect(Earning.kind.value, 'entries.earning');
    expect(Transfer.kind.value, 'entries.transfer');
    expect(OpeningBalance.kind.value, 'accounts.opening');
    expect(homeCurrency.value, 'TWD');
  });
}
