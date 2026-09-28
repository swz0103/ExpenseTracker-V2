import 'package:foundation_values/foundation_values.dart';
import 'package:reports/reports.dart';
import 'package:test/test.dart';

void main() {
  final twd = Currency('TWD', 2), usd = Currency('USD', 2);
  AssetBalanceFact fact(
    Currency currency,
    String amount, {
    bool included = true,
  }) => AssetBalanceFact(
    PublicId.generate(),
    Money.parse(currency, amount),
    included,
  );

  test('current balances remain per-currency and respect inclusion', () {
    final cash = fact(twd, '100');
    final bank = fact(twd, '-20');
    final foreign = fact(usd, '7');
    final excluded = fact(twd, '999', included: false);
    final report = AssetReport.build([cash, bank, foreign, excluded]);
    expect(report.currencies.map((s) => s.currency.code), ['TWD', 'USD']);
    expect(report.currencies.first.total.majorText, '80.00');
    expect(report.currencies.first.accounts.map((s) => s.accountId), [
      cash.accountId,
      bank.accountId,
    ]);
    expect(report.currencies.last.total.majorText, '7.00');
    expect(report.excludedCount, 1);
  });

  test('empty and excluded-only reports do not invent a grand total', () {
    expect(AssetReport.build([]).currencies, isEmpty);
    final report = AssetReport.build([fact(twd, '5', included: false)]);
    expect(report.currencies, isEmpty);
    expect(report.excludedCount, 1);
  });

  test('duplicate account and overflow reject the entire report', () {
    final row = fact(twd, '1');
    expect(() => AssetReport.build([row, row]), throwsFormatException);
    expect(
      () => AssetReport.build([
        AssetBalanceFact(
          PublicId.generate(),
          Money(twd, Money.maxMinorUnits),
          true,
        ),
        fact(twd, '1'),
      ]),
      throwsA(isA<MoneyException>()),
    );
  });
}
