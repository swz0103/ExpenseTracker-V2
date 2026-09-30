import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  final accountId = PublicId.generate();
  final instrumentId = PublicId.generate();
  final usd = Currency('USD', 2);
  final eur = Currency('EUR', 2);
  Money amount(String text, [Currency? currency]) =>
      Money.parse(currency ?? usd, text);
  InvestmentHoldingLot lot(
    String quantity,
    String cost, {
    PublicId? id,
    PublicId? account,
    PublicId? instrument,
    Currency? currency,
  }) => InvestmentHoldingLot(
    id: id ?? PublicId.generate(),
    investmentAccountId: account ?? accountId,
    instrumentId: instrument ?? instrumentId,
    acquiredOn: BusinessDate(2026, 1, 1),
    remainingQuantity: ShareQuantity.parse(quantity),
    remainingCost: amount(cost, currency),
    expectedVersion: 1,
  );
  InvestmentPerformance calculate({
    List<InvestmentHoldingLot>? lots,
    List<Money>? realized,
    List<Money>? dividends,
    ShareUnitPrice? quote,
  }) => InvestmentPerformance.calculate(
    investmentAccountId: accountId,
    instrumentId: instrumentId,
    currency: usd,
    openLots: lots ?? [lot('1.5', '12.00'), lot('0.25', '3.00')],
    realizedResults: realized ?? [amount('-1.20')],
    netDividends: dividends ?? [amount('0.70')],
    usablePrice: quote,
  );
  Matcher problem(InvestmentPerformanceError code) => throwsA(
    isA<InvestmentPerformanceException>().having(
      (error) => error.code,
      'code',
      code,
    ),
  );

  test('one exact quote produces position value and total return', () {
    final result = calculate(quote: ShareUnitPrice.parse(usd, '10'));
    expect(result.quantityUnits, BigInt.parse('1750000000000'));
    expect(result.remainingCost, amount('15.00'));
    expect(result.marketValue, amount('17.50'));
    expect(result.unrealizedResult, amount('2.50'));
    expect(result.realizedResult, amount('-1.20'));
    expect(result.netDividends, amount('0.70'));
    expect(result.totalReturn, amount('2.00'));
  });

  test('missing or unusable mark cannot fabricate unrealized return', () {
    final result = calculate();
    expect(result.remainingCost, amount('15.00'));
    expect(result.realizedResult, amount('-1.20'));
    expect(result.marketValue, isNull);
    expect(result.unrealizedResult, isNull);
    expect(result.totalReturn, isNull);
  });

  test('closed position has zero current value without a quote', () {
    final result = calculate(
      lots: [],
      realized: [amount('25.00')],
      dividends: [amount('2.00')],
    );
    expect(result.marketValue, amount('0.00'));
    expect(result.totalReturn, amount('27.00'));
  });

  test('one final quantization handles fractional shares', () {
    final result = calculate(
      lots: [lot('0.005', '0.01'), lot('0.005', '0.01')],
      realized: [],
      dividends: [],
      quote: ShareUnitPrice.parse(usd, '1.5'),
    );
    expect(result.marketValue, amount('0.02'));
    expect(result.unrealizedResult, amount('0.00'));
  });

  test('rejects duplicate lots and cross-account/currency facts', () {
    final first = lot('1', '1');
    expect(
      () => calculate(lots: [first, first]),
      problem(InvestmentPerformanceError.duplicateLot),
    );
    expect(
      () => calculate(lots: [lot('1', '1', account: PublicId.generate())]),
      problem(InvestmentPerformanceError.identityMismatch),
    );
    expect(
      () => calculate(lots: [lot('1', '1', instrument: PublicId.generate())]),
      problem(InvestmentPerformanceError.identityMismatch),
    );
    expect(
      () => calculate(lots: [lot('1', '1', currency: eur)]),
      problem(InvestmentPerformanceError.currencyMismatch),
    );
    expect(
      () => calculate(realized: [amount('1', eur)]),
      problem(InvestmentPerformanceError.currencyMismatch),
    );
    expect(
      () => calculate(quote: ShareUnitPrice.parse(eur, '1')),
      problem(InvestmentPerformanceError.currencyMismatch),
    );
  });

  test('sum overflow is rejected before display', () {
    expect(
      () => calculate(
        lots: [],
        realized: [Money(usd, Money.maxMinorUnits), amount('0.01')],
        dividends: [],
      ),
      throwsA(isA<MoneyException>()),
    );
  });
}
