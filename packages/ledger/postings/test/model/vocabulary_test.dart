import 'package:kernel/kernel.dart';
import 'package:ledger_entries/model.dart' show AccountKind;
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:test/test.dart' hide Tags;

void main() {
  test('what is owed is a liability, the rest an asset', () {
    expect(
      {for (final k in AccountKind.values) k.name: classOf(k)},
      {
        'cash': AccountClass.asset,
        'bank': AccountClass.asset,
        'wallet': AccountClass.asset,
        'card': AccountClass.liability,
        'loan': AccountClass.liability,
        'receivable': AccountClass.asset,
      },
    );
  });

  test('the accounts and streams by name', () {
    expect(moneyAccount('b').value, 'acct:b');
    expect(pendingInstalments(moneyAccount('c')).value, 'acct:c:instalments');
    expect(categoryAccount('早餐', income: false).value, 'cat:spending:早餐');
    expect(categoryAccount('早餐', income: true).value, 'cat:income:早餐');
    expect(
      namedCategoryAccount('早餐', income: false).value,
      'catname:spending:早餐',
    );
    expect(namedCategoryAccount('早餐', income: true).value, 'catname:income:早餐');
    expect(holdingAccount('2330').value, 'holding:2330');
    expect(Streams.holding('2330'), 'holding:2330');
    expect(Streams.instalments(moneyAccount('c')), 'instalments:acct:c');
    expect((Slots.fx, Slots.instalments), ('fx', 'instalments'));
    expect(Tags.money, {
      'cash',
      'bank',
      'wallet',
      'card',
      'loan',
      'receivable',
      'missing',
    });
  });

  test('every book has the fixed accounts, realised gains outside the '
      'income report', () {
    expect(
      [for (final a in Fixed.all) a.id],
      [
        Fixed.openingBalances,
        Fixed.openingPositions,
        Fixed.currencyTrading,
        Fixed.realisedGains,
        Fixed.dividends,
        Fixed.outOfHoldings,
      ],
    );
    expect(
      [for (final a in Fixed.all) a.inFlowReports],
      [true, true, true, false, true, true],
    );
    expect(Owners.legacy, isNot(Owners.accounts));
  });
}
