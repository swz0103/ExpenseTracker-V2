import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency.of('TWD');
  Money ntd(int units) => Money(twd, BigInt.from(units));
  ShareQuantity shares(String text) => ShareQuantity.parse(text);
  Matcher fails(InvestmentError code) => throwsA(
    isA<InvestmentException>().having((error) => error.code, 'code', code),
  );

  test('the fee is 0.1425% after discount, rounded down, with minimums', () {
    final full = TaiwanTradeCharges();
    expect(full.fee(ntd(100000), shares('1000')), ntd(142));
    expect(full.fee(ntd(5000), shares('1000')), ntd(20));
    // An odd lot only pays the odd-lot minimum.
    expect(full.fee(ntd(5000), shares('10')), ntd(7));
    final discounted = TaiwanTradeCharges(discountBasisPoints: 2800);
    expect(discounted.fee(ntd(100000), shares('1000')), ntd(39));
    expect(discounted.fee(ntd(300), shares('3')), ntd(1));
    expect(full.fee(ntd(0), shares('1')), ntd(0));
  });

  test('sell tax depends on the instrument and day trading', () {
    final charges = TaiwanTradeCharges();
    Money tax(InstrumentKind kind, {bool dayTrade = false}) => charges.sellTax(
      ntd(100000),
      shares('1000'),
      kind: kind,
      dayTrade: dayTrade,
    );
    expect(tax(InstrumentKind.stock), ntd(300));
    expect(tax(InstrumentKind.stock, dayTrade: true), ntd(150));
    expect(tax(InstrumentKind.etf), ntd(100));
    expect(tax(InstrumentKind.etf, dayTrade: true), ntd(100));
  });

  test('bad inputs are refused', () {
    final charges = TaiwanTradeCharges();
    expect(
      () => charges.fee(Money.parse(Currency.of('USD'), '10'), shares('1')),
      fails(InvestmentError.currencyMismatch),
    );
    expect(
      () => charges.fee(ntd(100), shares('0.5')),
      fails(InvestmentError.fractionalShares),
    );
    expect(
      () => TaiwanTradeCharges(discountBasisPoints: 0),
      fails(InvestmentError.invalidInput),
    );
  });

  test('the NHI premium applies from NT\$20,000, up to NT\$10 million', () {
    expect(supplementaryPremium(ntd(19999)), ntd(0));
    expect(supplementaryPremium(ntd(20000)), ntd(422));
    expect(supplementaryPremium(ntd(12345678)), ntd(211000));
    expect(supplementaryPremium(ntd(30000), basisPoints: 200), ntd(600));
  });

  test('trades settle two exchange days later', () {
    final calendar = BankingCalendar(holidays: {BusinessDate(2026, 10, 9)});
    final thursday = BusinessDate(2026, 10, 8);
    expect(
      taiwanSettlementDate(thursday, calendar),
      BusinessDate(2026, 10, 13),
    );
  });
}
