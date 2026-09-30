import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2);
  final eur = Currency('EUR', 2);
  final broker = BrokerIdentity(
    id: PublicId.generate(),
    workspace: workspace,
    name: 'Synthetic broker',
  );
  final cashId = PublicId.generate();
  final account = InvestmentAccount(
    id: PublicId.generate(),
    workspace: workspace,
    brokerId: broker.id,
    fundingCashAccountId: cashId,
    name: 'Synthetic portfolio',
    expectedVersion: 1,
  );
  final funding = FundingCashAccount(
    id: cashId,
    workspace: workspace,
    currency: usd,
    expectedVersion: 2,
  );
  final instrument = InvestmentInstrument(
    id: PublicId.generate(),
    kind: InstrumentKind.etf,
    marketCode: 'XNAS',
    symbol: 'TEST',
    name: 'Synthetic ETF',
    tradingCurrency: usd,
  );
  Money usdMoney(String value) => Money.parse(usd, value);
  InvestmentDividendPreview dividend({
    BrokerIdentity? selectedBroker,
    InvestmentAccount? selectedAccount,
    FundingCashAccount? selectedFunding,
    Money? gross,
    Money? tax,
    Money? fee,
    Money? net,
    OperationKey? operation,
  }) => InvestmentDividendPreview.create(
    id: PublicId.generate(),
    operation:
        operation ?? OperationKey(workspace, OperationId(PublicId.generate())),
    paidOn: BusinessDate(2026, 9, 30),
    broker: selectedBroker ?? broker,
    account: selectedAccount ?? account,
    instrument: instrument,
    funding: selectedFunding ?? funding,
    gross: gross ?? usdMoney('10.00'),
    withholdingTax: tax ?? usdMoney('1.50'),
    fee: fee ?? usdMoney('0.25'),
    reportedNet: net ?? usdMoney('8.25'),
  );
  Matcher error(InvestmentDividendError code) => throwsA(
    isA<InvestmentDividendException>().having((e) => e.code, 'code', code),
  );

  test('broker-reported gross, tax and fee exactly match credited cash', () {
    final row = dividend();
    expect(row.netCashCredit, usdMoney('8.25'));
    expect(row.gross, usdMoney('10.00'));
    expect(row.withholdingTax, usdMoney('1.50'));
    expect(row.fee, usdMoney('0.25'));
    expect(row.instrument.id, instrument.id);
    expect(row.funding.id, cashId);
  });

  test('rejects guessed net and nonpositive payout', () {
    expect(
      () => dividend(net: usdMoney('8.26')),
      error(InvestmentDividendError.netMismatch),
    );
    expect(
      () => dividend(net: usdMoney('0.00')),
      error(InvestmentDividendError.invalidInput),
    );
    expect(
      () => dividend(tax: usdMoney('10.00')),
      error(InvestmentDividendError.netMismatch),
    );
    expect(
      () => dividend(gross: usdMoney('0.00')),
      error(InvestmentDividendError.invalidInput),
    );
  });

  test('rejects currency and identity mismatches without silent FX', () {
    expect(
      () => dividend(gross: Money.parse(eur, '10.00')),
      error(InvestmentDividendError.currencyMismatch),
    );
    expect(
      () => dividend(
        selectedFunding: FundingCashAccount(
          id: cashId,
          workspace: workspace,
          currency: eur,
          expectedVersion: 2,
        ),
      ),
      error(InvestmentDividendError.currencyMismatch),
    );
    expect(
      () => dividend(
        selectedBroker: BrokerIdentity(
          id: PublicId.generate(),
          workspace: workspace,
          name: 'Other',
        ),
      ),
      error(InvestmentDividendError.brokerMismatch),
    );
    expect(
      () => dividend(
        operation: OperationKey(
          WorkspaceId(PublicId.generate()),
          OperationId(PublicId.generate()),
        ),
      ),
      error(InvestmentDividendError.workspaceMismatch),
    );
  });
}
