import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2);
  final eur = Currency('EUR', 2);
  final date = BusinessDate(2026, 9, 30);
  final broker = BrokerIdentity(
    id: PublicId.generate(),
    workspace: workspace,
    name: 'Synthetic Broker',
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
    expectedVersion: 3,
  );
  final stock = InvestmentInstrument(
    id: PublicId.generate(),
    kind: InstrumentKind.stock,
    marketCode: 'XNAS',
    symbol: 'TEST',
    name: 'Synthetic stock',
    tradingCurrency: usd,
  );
  Money money(String text, [Currency? currency]) =>
      Money.parse(currency ?? usd, text);
  Matcher investmentError(InvestmentError code) => throwsA(
    isA<InvestmentException>().having((error) => error.code, 'code', code),
  );
  InvestmentBuyPreview buy({
    BrokerIdentity? selectedBroker,
    InvestmentAccount? selectedAccount,
    InvestmentInstrument? selectedInstrument,
    FundingCashAccount? selectedFunding,
    OperationKey? operation,
    PublicId? buyId,
    PublicId? lotId,
    ShareQuantity? quantity,
    ShareUnitPrice? unitPrice,
    Money? gross,
    Money? fee,
    Money? tax,
  }) => InvestmentBuyPreview.create(
    id: buyId ?? PublicId.generate(),
    lotId: lotId ?? PublicId.generate(),
    operation:
        operation ?? OperationKey(workspace, OperationId(PublicId.generate())),
    tradedOn: date,
    broker: selectedBroker ?? broker,
    account: selectedAccount ?? account,
    instrument: selectedInstrument ?? stock,
    funding: selectedFunding ?? funding,
    quantity: quantity ?? ShareQuantity.parse('10'),
    unitPrice: unitPrice ?? ShareUnitPrice.parse(usd, '5.00'),
    executedGross: gross ?? money('50.00'),
    fee: fee ?? money('1.00'),
    tax: tax ?? money('0.00'),
  );

  test('10 shares at USD 5 plus USD 1 fee proposes one USD 51 debit', () {
    final preview = buy();
    expect(preview.gross, money('50.00'));
    expect(preview.fee, money('1.00'));
    expect(preview.tax, money('0.00'));
    expect(preview.cashDebit, money('51.00'));
    expect(preview.lot.acquisitionCashCost, preview.cashDebit);
    expect(preview.lot.quantity, ShareQuantity.parse('10.0'));
    expect(preview.lot.unitPrice, ShareUnitPrice.parse(usd, '5'));
    expect(preview.lot.buyId, preview.id);
    expect(preview.lot.investmentAccountId, account.id);
    expect(preview.lot.instrumentId, stock.id);
    expect(preview.lot.acquiredOn, date);
    expect(preview.funding.id, cashId);
  });

  test('fractional shares retain exact quote and round once at settlement', () {
    final preview = buy(
      quantity: ShareQuantity.parse('0.125'),
      unitPrice: ShareUnitPrice.parse(usd, '42.99'),
      gross: money('5.37'),
      fee: money('0.03'),
      tax: money('0.02'),
    );
    expect(preview.exactGrossNumerator, BigInt.from(537375));
    expect(preview.exactGrossDenominator, BigInt.from(100000));
    expect(preview.gross, money('5.37'));
    expect(preview.cashDebit, money('5.42'));
    expect(InvestmentBuyPreview.settlementRoundingPolicy, Money.roundingPolicy);
  });

  test('half-cent rounds away from zero and settlement must be explicit', () {
    final preview = buy(
      quantity: ShareQuantity.parse('1'),
      unitPrice: ShareUnitPrice.parse(usd, '0.005'),
      gross: money('0.01'),
      fee: money('0.00'),
    );
    expect(preview.cashDebit, money('0.01'));
    expect(
      () => buy(
        quantity: ShareQuantity.parse('0.001'),
        unitPrice: ShareUnitPrice.parse(usd, '0.01'),
        gross: money('0.01'),
      ),
      investmentError(InvestmentError.grossMismatch),
    );
    expect(
      () => buy(gross: money('50.01')),
      investmentError(InvestmentError.grossMismatch),
    );
  });

  test(
    'quantity and price reject zero, floats, exponent and excess precision',
    () {
      for (final text in [
        '0',
        '-1',
        '1e3',
        '1,000',
        ' 1',
        '01',
        '0.0000000000001',
      ]) {
        expect(
          () => ShareQuantity.parse(text),
          investmentError(InvestmentError.invalidInput),
        );
        expect(
          () => ShareUnitPrice.parse(usd, text),
          investmentError(InvestmentError.invalidInput),
        );
      }
      expect(
        ShareQuantity.parse('0.000000000001').toString(),
        '0.000000000001',
      );
      expect(ShareQuantity.parse('1.5000'), ShareQuantity.parse('1.5'));
    },
  );

  test('negative fees or taxes and duplicate buy/lot ID are rejected', () {
    expect(
      () => buy(fee: money('-0.01')),
      investmentError(InvestmentError.invalidInput),
    );
    expect(
      () => buy(tax: money('-0.01')),
      investmentError(InvestmentError.invalidInput),
    );
    final sameId = PublicId.generate();
    expect(
      () => buy(buyId: sameId, lotId: sameId),
      investmentError(InvestmentError.duplicateIdentity),
    );
  });

  test('all values must share trade currency; no implicit FX', () {
    final euroInstrument = InvestmentInstrument(
      id: PublicId.generate(),
      kind: InstrumentKind.etf,
      marketCode: 'XETR',
      symbol: 'TEST',
      name: 'Synthetic ETF',
      tradingCurrency: eur,
    );
    expect(
      () => buy(selectedInstrument: euroInstrument),
      investmentError(InvestmentError.currencyMismatch),
    );
    expect(
      () => buy(fee: money('1', eur)),
      investmentError(InvestmentError.currencyMismatch),
    );
    expect(
      () => buy(tax: money('1', eur)),
      investmentError(InvestmentError.currencyMismatch),
    );
    expect(
      () => buy(unitPrice: ShareUnitPrice.parse(eur, '5')),
      investmentError(InvestmentError.currencyMismatch),
    );
    expect(
      () => buy(gross: money('50', eur)),
      investmentError(InvestmentError.currencyMismatch),
    );
  });

  test('workspace, broker and linked funding identities must match', () {
    final otherWorkspace = WorkspaceId(PublicId.generate());
    expect(
      () => buy(
        operation: OperationKey(
          otherWorkspace,
          OperationId(PublicId.generate()),
        ),
      ),
      investmentError(InvestmentError.workspaceMismatch),
    );
    expect(
      () => buy(
        selectedBroker: BrokerIdentity(
          id: PublicId.generate(),
          workspace: workspace,
          name: 'Different broker',
        ),
      ),
      investmentError(InvestmentError.brokerMismatch),
    );
    expect(
      () => buy(
        selectedFunding: FundingCashAccount(
          id: PublicId.generate(),
          workspace: workspace,
          currency: usd,
          expectedVersion: 1,
        ),
      ),
      investmentError(InvestmentError.fundingAccountMismatch),
    );
  });

  test('quote and total cash debit reject signed 64-bit overflow', () {
    expect(
      () => buy(
        quantity: ShareQuantity.parse('1'),
        unitPrice: ShareUnitPrice.parse(usd, '92233720368547758.08'),
        gross: Money(usd, Money.maxMinorUnits),
      ),
      investmentError(InvestmentError.overflow),
    );
    expect(
      () => buy(
        quantity: ShareQuantity.parse('1'),
        unitPrice: ShareUnitPrice.parse(usd, '92233720368547758.07'),
        gross: Money(usd, Money.maxMinorUnits),
        fee: money('0.01'),
      ),
      investmentError(InvestmentError.overflow),
    );
  });
}
