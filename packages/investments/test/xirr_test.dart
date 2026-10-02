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

  test('three roots are never presented as a unique return', () {
    final result = calculateInvestmentXirr(
      currency: usd,
      flows: [
        flow(2024, '-6.00'),
        flow(2025, '29.00'),
        flow(2026, '-46.00'),
        flow(2027, '24.00'),
      ],
    );
    expect(
      result.status,
      anyOf(
        InvestmentXirrStatus.multipleRoots,
        InvestmentXirrStatus.ambiguousRoots,
      ),
    );
    expect(result.annualRate, isNull);
  });

  test('a close root pair hidden between grid points stays ambiguous', () {
    // In y = 1 / (1 + rate), these coefficients have roots at 0.500,
    // 0.501 and 0.750. A coarse sign grid can see only the separated root
    // because the close pair crosses twice between adjacent samples.
    final result = calculateInvestmentXirr(
      currency: usd,
      flows: [
        flow(2024, '-1878750.00'),
        flow(2025, '10012500.00'),
        flow(2026, '-17510000.00'),
        flow(2027, '10000000.00'),
      ],
    );
    expect(result.status, InvestmentXirrStatus.ambiguousRoots);
    expect(result.annualRate, isNull);
  });

  test('an even-multiplicity root cannot be certified by sign sampling', () {
    // Polynomial in y: (y - 0.5)^2 * (y - 0.75).
    final result = calculateInvestmentXirr(
      currency: usd,
      flows: [
        flow(2024, '-3.00'),
        flow(2025, '16.00'),
        flow(2026, '-28.00'),
        flow(2027, '16.00'),
      ],
    );
    expect(result.status, InvestmentXirrStatus.ambiguousRoots);
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

  test('bounded solver does not mislabel extreme return as impossible', () {
    final result = calculateInvestmentXirr(
      currency: usd,
      flows: [flow(2025, '-0.01'), flow(2026, '10000000000.00')],
    );
    expect(result.status, InvestmentXirrStatus.outsideSearchRange);
    expect(result.annualRate, isNull);
  });

  test('a root on the documented upper boundary remains available', () {
    // 2024-01-01 through 2028-01-01 is exactly 1461 days = 4 ACT/365.25
    // years. 1001^4 therefore places ln(1 + rate) on the upper boundary.
    final result = calculateInvestmentXirr(
      currency: usd,
      flows: [flow(2024, '-0.01'), flow(2028, '10040060040.01')],
    );
    expect(result.status, InvestmentXirrStatus.available);
    expect(result.annualRate!, closeTo(1000, 1e-6));
  });
}
