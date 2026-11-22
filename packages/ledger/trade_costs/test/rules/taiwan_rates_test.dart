import 'package:core/foundation_values.dart';
import 'package:ledger_trade_costs/model/trade_values.dart';
import 'package:ledger_trade_costs/rules/taiwan_rates.dart';
import 'package:test/test.dart';

void main() {
  test('the rows are oldest first, from 2016', () {
    final froms = [for (final r in TaiwanRates.history) r.from];
    expect(froms, [
      BusinessDate(2016, 1, 1),
      BusinessDate(2017, 1, 1),
      BusinessDate(2017, 4, 28),
      BusinessDate(2021, 1, 1),
      BusinessDate(2027, 1, 1),
      BusinessDate(2028, 1, 1),
    ]);
  });

  test('a day takes the row in force on it', () {
    final before = TaiwanRates.on(BusinessDate(2017, 4, 27));
    expect(before.dayTradeTax, 30);
    final halved = TaiwanRates.on(BusinessDate(2017, 4, 28));
    expect(halved.dayTradeTax, 15);
    expect(TaiwanRates.on(BusinessDate(2020, 12, 31)).premiumBasisPoints, 191);
    expect(TaiwanRates.on(BusinessDate(2021, 1, 1)).premiumBasisPoints, 211);
  });

  test('the end dates the law sets: bond ETFs in 2027, day trades in 2028', () {
    expect(TaiwanRates.on(BusinessDate(2026, 12, 31)).bondEtfTax, 0);
    expect(TaiwanRates.on(BusinessDate(2027, 1, 1)).bondEtfTax, 10);
    expect(TaiwanRates.on(BusinessDate(2027, 12, 31)).dayTradeTax, 15);
    expect(TaiwanRates.on(BusinessDate(2028, 1, 1)).dayTradeTax, 30);
  });

  test('a day past the last row takes the last row', () {
    final far = TaiwanRates.on(BusinessDate(2040, 6, 1));
    expect(far, same(TaiwanRates.history.last));
  });

  test('before 2016 there is no rate', () {
    expect(
      () => TaiwanRates.on(BusinessDate(2015, 12, 31)),
      throwsA(
        isA<InvestmentException>().having(
          (e) => e.code,
          'code',
          InvestmentError.invalidInput,
        ),
      ),
    );
  });
}
