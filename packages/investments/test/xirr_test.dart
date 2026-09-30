import 'package:foundation_values/foundation_values.dart';
import 'package:investments/src/xirr.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency('USD', 2);
  final eur = Currency('EUR', 2);
  InvestmentCashFlow flow(int year, String amount, [Currency? currency]) =>
      InvestmentCashFlow(
        BusinessDate(year, 1, 1),
        Money.parse(currency ?? usd, amount),
      );

  test('one investment and one exit produce a near-ten-percent XIRR', () {
    final result = calculateInvestmentXirr(
      currency: usd,
      flows: [flow(2025, '-100.00'), flow(2026, '110.00')],
    );
    expect(result.status, InvestmentXirrStatus.available);
    expect(result.annualRate!, closeTo(0.1, 0.001));
  });

  test('cash dividend and final mark both contribute on their own dates', () {
    final result = calculateInvestmentXirr(
      currency: usd,
      flows: [flow(2024, '-100.00'), flow(2025, '5.00'), flow(2026, '110.00')],
    );
    expect(result.status, InvestmentXirrStatus.available);
    expect(result.annualRate!, greaterThan(0.07));
    expect(result.annualRate!, lessThan(0.09));
  });

  test('all same-day, one sign or no sign change has no solution', () {
    for (final flows in [
      [flow(2025, '-100.00'), flow(2025, '110.00')],
      [flow(2025, '-100.00'), flow(2026, '-10.00')],
      [flow(2025, '-100.00'), flow(2026, '0.00')],
    ]) {
      expect(
        calculateInvestmentXirr(currency: usd, flows: flows).status,
        InvestmentXirrStatus.noSolution,
      );
    }
  });

  test('non-monotone cash flows with two plausible roots stay ambiguous', () {
    final result = calculateInvestmentXirr(
      currency: usd,
      flows: [
        flow(2024, '-100.00'),
        flow(2025, '230.00'),
        flow(2026, '-132.00'),
      ],
    );
    expect(result.status, InvestmentXirrStatus.multipleRoots);
    expect(result.annualRate, isNull);
  });

  test('different currencies are rejected rather than summed', () {
    expect(
      () => calculateInvestmentXirr(
        currency: usd,
        flows: [flow(2025, '-100.00'), flow(2026, '110.00', eur)],
      ),
      throwsA(
        isA<MoneyException>().having(
          (error) => error.code,
          'code',
          MoneyError.currencyMismatch,
        ),
      ),
    );
  });

  test('long-dated terms do not overflow the rate solver', () {
    final result = calculateInvestmentXirr(
      currency: usd,
      flows: [flow(1900, '-100.00'), flow(2100, '110.00')],
    );
    expect(result.status, InvestmentXirrStatus.available);
    expect(result.annualRate!, greaterThan(0));
    expect(result.annualRate!, lessThan(0.001));
  });
}
