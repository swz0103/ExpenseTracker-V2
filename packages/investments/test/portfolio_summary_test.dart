import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  final usd = Currency('USD', 2);
  final eur = Currency('EUR', 2);

  InvestmentPositionPerformance position({
    required Currency currency,
    String? quantity,
    String cost = '0.00',
    String realized = '0.00',
    String dividends = '0.00',
    String? price,
    Money? realizedMoney,
    PublicId? accountId,
    PublicId? instrumentId,
    Currency? declaredCurrency,
  }) {
    final account = accountId ?? PublicId.generate();
    final instrument = instrumentId ?? PublicId.generate();
    final lots = quantity == null
        ? <InvestmentHoldingLot>[]
        : [
            InvestmentHoldingLot(
              id: PublicId.generate(),
              investmentAccountId: account,
              instrumentId: instrument,
              acquiredOn: BusinessDate(2026, 1, 2),
              remainingQuantity: ShareQuantity.parse(quantity),
              remainingCost: Money.parse(currency, cost),
              expectedVersion: 1,
            ),
          ];
    return InvestmentPositionPerformance(
      investmentAccountId: account,
      instrumentId: instrument,
      tradingCurrency: declaredCurrency ?? currency,
      performance: InvestmentPerformance.calculate(
        investmentAccountId: account,
        instrumentId: instrument,
        currency: currency,
        openLots: lots,
        realizedResults: [realizedMoney ?? Money.parse(currency, realized)],
        netDividends: [Money.parse(currency, dividends)],
        usablePrice: price == null
            ? null
            : ShareUnitPrice.parse(currency, price),
      ),
    );
  }

  Matcher problem(InvestmentPortfolioError code) => throwsA(
    isA<InvestmentPortfolioException>().having(
      (error) => error.code,
      'code',
      code,
    ),
  );

  test('same-currency open and closed positions reconcile exact totals', () {
    final summary = InvestmentPortfolioSummary.calculate([
      position(
        currency: usd,
        quantity: '2',
        cost: '100.00',
        realized: '5.00',
        dividends: '3.00',
        price: '60.00',
      ),
      position(
        currency: usd,
        quantity: '1',
        cost: '50.00',
        realized: '-2.00',
        dividends: '1.00',
        price: '40.00',
      ),
      position(currency: usd, realized: '4.00', dividends: '2.00'),
    ]).byCurrency[usd]!;
    expect(summary.positionCount, 3);
    expect(summary.openPositionCount, 2);
    expect(summary.missingPriceCount, 0);
    expect(summary.hasCompleteValuation, isTrue);
    expect(summary.remainingCost, Money.parse(usd, '150.00'));
    expect(summary.realizedResult, Money.parse(usd, '7.00'));
    expect(summary.netDividends, Money.parse(usd, '6.00'));
    expect(summary.marketValue, Money.parse(usd, '160.00'));
    expect(summary.unrealizedResult, Money.parse(usd, '10.00'));
    expect(summary.totalReturn, Money.parse(usd, '23.00'));
  });

  test('currencies remain separate and empty portfolio has no fake total', () {
    final summary = InvestmentPortfolioSummary.calculate([
      position(currency: usd, quantity: '1', cost: '10.00', price: '12.00'),
      position(currency: eur, quantity: '1', cost: '10.00', price: '8.00'),
    ]);
    expect(summary.byCurrency.keys, containsAll([usd, eur]));
    expect(summary.byCurrency.length, 2);
    expect(summary.byCurrency[usd]!.marketValue, Money.parse(usd, '12.00'));
    expect(summary.byCurrency[eur]!.marketValue, Money.parse(eur, '8.00'));
    expect(summary.byCurrency[usd]!.totalReturn, Money.parse(usd, '2.00'));
    expect(summary.byCurrency[eur]!.totalReturn, Money.parse(eur, '-2.00'));
    expect(InvestmentPortfolioSummary.calculate([]).byCurrency, isEmpty);
  });

  test('one missing open quote hides only that currency valuation totals', () {
    final summary = InvestmentPortfolioSummary.calculate([
      position(
        currency: usd,
        quantity: '1',
        cost: '10.00',
        realized: '2.00',
        dividends: '1.00',
        price: '12.00',
      ),
      position(
        currency: usd,
        quantity: '2',
        cost: '20.00',
        realized: '-1.00',
        dividends: '0.50',
      ),
      position(currency: eur, quantity: '1', cost: '4.00', price: '5.00'),
    ]);
    final dollars = summary.byCurrency[usd]!;
    expect(dollars.openPositionCount, 2);
    expect(dollars.missingPriceCount, 1);
    expect(dollars.hasCompleteValuation, isFalse);
    expect(dollars.remainingCost, Money.parse(usd, '30.00'));
    expect(dollars.realizedResult, Money.parse(usd, '1.00'));
    expect(dollars.netDividends, Money.parse(usd, '1.50'));
    expect(dollars.marketValue, isNull);
    expect(dollars.unrealizedResult, isNull);
    expect(dollars.totalReturn, isNull);
    expect(summary.byCurrency[eur]!.hasCompleteValuation, isTrue);
    expect(summary.byCurrency[eur]!.marketValue, Money.parse(eur, '5.00'));
  });

  test('duplicate position and declared currency mismatch are rejected', () {
    final first = position(
      currency: usd,
      quantity: '1',
      cost: '1.00',
      price: '2.00',
    );
    expect(
      () => InvestmentPortfolioSummary.calculate([first, first]),
      problem(InvestmentPortfolioError.duplicatePosition),
    );
    final wrong = position(
      currency: usd,
      quantity: '1',
      cost: '1.00',
      price: '2.00',
      declaredCurrency: eur,
    );
    expect(
      () => InvestmentPortfolioSummary.calculate([wrong]),
      problem(InvestmentPortfolioError.currencyMismatch),
    );
  });

  test('cross-position sum overflow rejects the whole currency summary', () {
    final first = position(
      currency: usd,
      realizedMoney: Money(usd, Money.maxMinorUnits),
    );
    final second = position(currency: usd, realized: '0.01');
    expect(
      () => InvestmentPortfolioSummary.calculate([first, second]),
      throwsA(
        isA<MoneyException>().having(
          (error) => error.code,
          'code',
          MoneyError.overflow,
        ),
      ),
    );
  });
}
