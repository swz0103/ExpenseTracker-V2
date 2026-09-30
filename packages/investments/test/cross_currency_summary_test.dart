import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

InvestmentPositionPerformance position({
  required Currency currency,
  required String cost,
  String? price,
  String realized = '0',
  String dividends = '0',
}) {
  final account = PublicId.generate();
  final instrument = PublicId.generate();
  return InvestmentPositionPerformance(
    investmentAccountId: account,
    instrumentId: instrument,
    tradingCurrency: currency,
    performance: InvestmentPerformance.calculate(
      investmentAccountId: account,
      instrumentId: instrument,
      currency: currency,
      openLots: [
        InvestmentHoldingLot(
          id: PublicId.generate(),
          investmentAccountId: account,
          instrumentId: instrument,
          acquiredOn: BusinessDate(2026, 1, 2),
          remainingQuantity: ShareQuantity.parse('1'),
          remainingCost: Money.parse(currency, cost),
          expectedVersion: 1,
        ),
      ],
      realizedResults: [Money.parse(currency, realized)],
      netDividends: [Money.parse(currency, dividends)],
      usablePrice: price == null ? null : ShareUnitPrice.parse(currency, price),
    ),
  );
}

FxObservation rate(
  Currency base,
  Currency quote,
  String value,
  BusinessDate date, {
  String source = 'test-fx',
}) => FxObservation(
  rate: FxRate.parse(base, quote, value),
  source: source,
  asOf: date,
  retrievedAt: UtcInstant(DateTime.utc(2026, 9, 30, 8)),
);

PortfolioFxInput input(FxObservation observation, {bool inverse = false}) =>
    PortfolioFxInput(observation: observation, derivedInverse: inverse);

void main() {
  final usd = Currency('USD', 2);
  final twd = Currency('TWD', 2);
  final eur = Currency('EUR', 2);
  final date = BusinessDate(2026, 9, 30);

  test('exact rates convert complete currency rows into one report total', () {
    final original = InvestmentPortfolioSummary.calculate([
      position(
        currency: usd,
        cost: '10',
        price: '12',
        realized: '1',
        dividends: '0.50',
      ),
      position(currency: eur, cost: '20', price: '18', realized: '-1'),
      position(currency: twd, cost: '100', price: '110'),
    ]);
    final result = CrossCurrencyInvestmentSummary.convert(
      original: original,
      reportingCurrency: twd,
      valuationDate: date,
      observations: [
        input(rate(usd, twd, '32', date, source: 'cbc-usd-twd')),
        input(rate(eur, twd, '35', date, source: 'eur-twd')),
      ],
    );
    expect(result.hasCompleteFx, isTrue);
    expect(result.hasCompleteValuation, isTrue);
    expect(result.remainingCost, Money.parse(twd, '1120'));
    expect(result.marketValue, Money.parse(twd, '1124'));
    expect(result.realizedResult, Money.parse(twd, '-3'));
    expect(result.netDividends, Money.parse(twd, '16'));
    expect(result.unrealizedResult, Money.parse(twd, '4'));
    expect(result.totalReturn, Money.parse(twd, '17'));
    expect(result.rows[usd]!.state, PortfolioFxState.exact);
    expect(result.rows[usd]!.observation!.source, 'cbc-usd-twd');
    expect(result.rows[twd]!.state, PortfolioFxState.identity);
    expect(result.rows[twd]!.observation, isNull);
  });

  test('inverse observation is explicit and exact', () {
    final original = InvestmentPortfolioSummary.calculate([
      position(currency: usd, cost: '10', price: '12'),
    ]);
    final result = CrossCurrencyInvestmentSummary.convert(
      original: original,
      reportingCurrency: twd,
      valuationDate: date,
      observations: [input(rate(twd, usd, '0.03125', date))],
    );
    expect(result.marketValue, Money.parse(twd, '384'));
    expect(result.rows[usd]!.derivedInverse, isTrue);
    expect(result.rows[usd]!.state, PortfolioFxState.exact);
  });

  test('missing FX hides every cross-currency grand total, not originals', () {
    final original = InvestmentPortfolioSummary.calculate([
      position(currency: usd, cost: '10', price: '12'),
      position(currency: twd, cost: '100', price: '110'),
    ]);
    final result = CrossCurrencyInvestmentSummary.convert(
      original: original,
      reportingCurrency: twd,
      valuationDate: date,
      observations: const [],
    );
    expect(result.hasCompleteFx, isFalse);
    expect(result.remainingCost, isNull);
    expect(result.marketValue, isNull);
    expect(result.rows[usd]!.state, PortfolioFxState.missing);
    expect(result.rows[usd]!.remainingCost, isNull);
    expect(result.rows[twd]!.marketValue, Money.parse(twd, '110'));
    expect(
      result.original.byCurrency[usd]!.marketValue,
      Money.parse(usd, '12'),
    );
  });

  test('earlier observation requires opt-in and retains actual date', () {
    final original = InvestmentPortfolioSummary.calculate([
      position(currency: usd, cost: '10', price: '12'),
    ]);
    final older = rate(usd, twd, '32', BusinessDate(2026, 9, 29));
    final rejected = CrossCurrencyInvestmentSummary.convert(
      original: original,
      reportingCurrency: twd,
      valuationDate: date,
      observations: [input(older)],
    );
    expect(rejected.rows[usd]!.state, PortfolioFxState.missing);
    expect(rejected.marketValue, isNull);

    final accepted = CrossCurrencyInvestmentSummary.convert(
      original: original,
      reportingCurrency: twd,
      valuationDate: date,
      observations: [input(older)],
      allowEarlier: true,
    );
    expect(accepted.rows[usd]!.state, PortfolioFxState.earlier);
    expect(accepted.rows[usd]!.observation!.asOf, BusinessDate(2026, 9, 29));
    expect(accepted.marketValue, Money.parse(twd, '384'));
  });

  test('missing position price hides valuation but keeps converted facts', () {
    final original = InvestmentPortfolioSummary.calculate([
      position(currency: usd, cost: '10', realized: '2', dividends: '1'),
    ]);
    final result = CrossCurrencyInvestmentSummary.convert(
      original: original,
      reportingCurrency: twd,
      valuationDate: date,
      observations: [input(rate(usd, twd, '32', date))],
    );
    expect(result.hasCompleteFx, isTrue);
    expect(result.remainingCost, Money.parse(twd, '320'));
    expect(result.realizedResult, Money.parse(twd, '64'));
    expect(result.netDividends, Money.parse(twd, '32'));
    expect(result.hasCompleteValuation, isFalse);
    expect(result.marketValue, isNull);
    expect(result.totalReturn, isNull);
  });

  test(
    'duplicate applicable observations fail instead of choosing silently',
    () {
      final original = InvestmentPortfolioSummary.calculate([
        position(currency: usd, cost: '10', price: '12'),
      ]);
      expect(
        () => CrossCurrencyInvestmentSummary.convert(
          original: original,
          reportingCurrency: twd,
          valuationDate: date,
          observations: [
            input(rate(usd, twd, '32', date, source: 'a')),
            input(rate(twd, usd, '0.03125', date, source: 'b')),
          ],
        ),
        throwsA(
          isA<CrossCurrencyPortfolioException>().having(
            (error) => error.code,
            'code',
            CrossCurrencyPortfolioError.duplicateRate,
          ),
        ),
      );
    },
  );

  test('empty portfolio has no fabricated zero grand total', () {
    final result = CrossCurrencyInvestmentSummary.convert(
      original: InvestmentPortfolioSummary.calculate([]),
      reportingCurrency: twd,
      valuationDate: date,
      observations: const [],
    );
    expect(result.rows, isEmpty);
    expect(result.remainingCost, isNull);
    expect(result.marketValue, isNull);
  });
}
