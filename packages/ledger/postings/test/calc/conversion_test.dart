import 'package:kernel/kernel.dart';
import 'package:ledger_postings/calc/conversion.dart';
import 'package:ledger_postings/model/intents.dart';
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:test/test.dart';

import '../support/book.dart';

const t = Fixed.currencyTrading;

List<(String, int, String)> shown(Posted p) => [
  for (final l in (p as Lines).lines)
    (l.account.value, l.amount, l.currency.value),
];

void main() {
  test('which lines are in a currency they must not be', () {
    final found = misplaced(
      [
        Line(usd, -100, homeCurrency), // money in the wrong currency
        Line(food, 100, usdCode), // a category not at home
        Line(food, 0, usdCode), // nothing: dropped anyway
        Line(bank, 5, homeCurrency), // right
        Line(Fixed.openingBalances, 1, usdCode), // equity takes any
      ],
      tree(),
      homeCurrency,
    );
    expect(found, [
      (index: 0, target: usdCode, money: true),
      (index: 1, target: homeCurrency, money: false),
    ]);
  });

  test('a worth is shared over a split in proportion, adding up exactly', () {
    final restated = restate(
      [
        Line(usd, -1000, usdCode),
        Line(food, 300, usdCode),
        Line(fees, 700, usdCode),
      ],
      accounts: tree(),
      home: homeCurrency,
      value: const Worth(3201),
      trading: t,
      slot: 'fx',
    );
    // 3201 × 30% = 960.3 and × 70% = 2240.7: 960 and 2241.
    expect(shown(restated), [
      ('acct:usd', -1000, 'USD'),
      ('cat:spending:food', 960, 'TWD'),
      ('cat:spending:fees', 2241, 'TWD'),
      ('equity:trading', 1000, 'USD'),
      ('equity:trading', -3201, 'TWD'),
    ]);
  });

  test('lines of two signs or two currencies are ambiguous', () {
    Posted r(List<Line> lines) => restate(
      lines,
      accounts: tree(),
      home: homeCurrency,
      value: const Worth(5),
      trading: t,
      slot: 'fx',
    );
    expect(
      (r([Line(food, 3, usdCode), Line(fees, -3, usdCode)]) as Refused).code,
      'fx.ambiguous',
    );
    expect(
      (r([
        Line(food, 3, usdCode),
        Line(fees, 3, const CurrencyCode('JPY')),
      ]) as Refused).code,
      'fx.ambiguous',
    );
  });

  test('nothing to restate and no value: the lines as they are', () {
    final lines = [Line(bank, -1, homeCurrency), Line(food, 1, homeCurrency)];
    expect(
      shown(
        restate(
          lines,
          accounts: tree(),
          home: homeCurrency,
          value: null,
          trading: t,
          slot: 'fx',
        ),
      ),
      [('acct:bank', -1, 'TWD'), ('cat:spending:food', 1, 'TWD')],
    );
  });
}
