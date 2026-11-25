import 'package:kernel/kernel.dart';
import 'package:ledger_postings/calc/statement.dart';
import 'package:ledger_postings/model/intents.dart';
import 'package:test/test.dart';

import '../support/book.dart';

void main() {
  test('what a statement still owes: payments in count, refunds do not', () {
    final b = book();
    for (final i in <LedgerIntent>[
      OpeningBalance(
        id: const IntentId('o'),
        seq: 0,
        account: card,
        amount: -1200,
      ),
      Spending(
        id: const IntentId('shoes'),
        date: day(9, 6),
        seq: 1,
        account: card,
        parts: [(food, 3000)],
      ),
      Earning(
        id: const IntentId('back'),
        date: day(9, 22),
        seq: 2,
        account: card,
        category: food,
        amount: 1000,
      ),
      Transfer(
        id: const IntentId('pay'),
        date: day(9, 25),
        seq: 3,
        from: bank,
        to: card,
        amount: 2000,
      ),
      Spending(
        id: const IntentId('later'),
        date: day(9, 26),
        seq: 4,
        account: card,
        parts: [(food, 50)],
      ),
    ]) {
      expect(keep(b, i), isA<Written>(), reason: i.id.value);
    }
    // Owed at the 9/20 close: 1200 + 3000 = 4200; paid since 2000; the
    // refund and the later spending are the next statement's.
    expect(statementDue(card, day(9, 20), b.reader, asOf: day(9, 30)), 2200);
    // Paid more than owed: nothing due.
    keep(
      b,
      Transfer(
        id: const IntentId('more'),
        date: day(9, 27),
        seq: 5,
        from: bank,
        to: card,
        amount: 9000,
      ),
    );
    expect(statementDue(card, day(9, 20), b.reader, asOf: day(9, 30)), 0);
    // As of the day before that payment it is 預定 (D25): not paid yet.
    expect(statementDue(card, day(9, 20), b.reader, asOf: day(9, 26)), 2200);
  });
}
