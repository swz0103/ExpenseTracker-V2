import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

import '../support/book.dart';

void main() {
  test('a line restated keeps its account, day, quantity and sub', () {
    final line = Line(bank, 100, twd, date: day(3, 1), quantity: 5, sub: 'a');
    final moved = line.restated(-3, usd);
    expect((moved.account, moved.amount, moved.currency), (bank, -3, usd));
    expect((moved.date, moved.quantity, moved.sub), (day(3, 1), 5, 'a'));
    const plain = Line(food, 1, twd);
    expect((plain.date, plain.quantity, plain.sub), (null, 0, ''));
  });

  test('two postings of the same values are equal', () {
    Posting p({int amount = 10}) => Posting(
      intent: const IntentId('i'),
      line: 0,
      account: bank,
      amount: amount,
      currency: twd,
      date: day(1, 2),
      seq: 3,
      quantity: 4,
      sub: 's',
    );
    expect(p(), p());
    expect(p().hashCode, p().hashCode);
    expect(p(), isNot(p(amount: 11)));
    expect('${p()}', 'Posting(i#0 20260102 bank 10 TWD q4 s)');
  });

  test('ids are their text', () {
    expect(const AccountId('a').value, 'a');
    expect(const IntentId('b').value, 'b');
    expect(const IntentType('c').value, 'c');
    expect(const OwnerId('d').value, 'd');
    expect(const CurrencyCode('TWD').value, 'TWD');
  });
}
