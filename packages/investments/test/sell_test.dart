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
    name: 'Synthetic Broker',
  );
  final cashId = PublicId.generate();
  final account = InvestmentAccount(
    id: PublicId.generate(),
    workspace: workspace,
    brokerId: broker.id,
    fundingCashAccountId: cashId,
    name: 'Synthetic Portfolio',
    expectedVersion: 2,
  );
  final funding = FundingCashAccount(
    id: cashId,
    workspace: workspace,
    currency: usd,
    expectedVersion: 3,
  );
  final instrument = InvestmentInstrument(
    id: PublicId.generate(),
    kind: InstrumentKind.etf,
    marketCode: 'XNAS',
    symbol: 'TEST',
    name: 'Synthetic ETF',
    tradingCurrency: usd,
  );
  final saleDate = BusinessDate(2026, 9, 30);
  final firstId = PublicId.parse('01999999-0000-7000-8000-000000000001');
  final secondId = PublicId.parse('01999999-0000-7000-8000-000000000002');
  final saleId = PublicId.generate();
  final operation = OperationKey(workspace, OperationId(PublicId.generate()));

  Money money(String input, [Currency? currency]) =>
      Money.parse(currency ?? usd, input);
  BigInt units(int shares) => BigInt.from(shares) * BigInt.from(10).pow(12);
  Matcher sellError(InvestmentSellError code) => throwsA(
    isA<InvestmentSellException>().having((error) => error.code, 'code', code),
  );
  InvestmentHoldingLot lot({
    PublicId? id,
    PublicId? accountId,
    PublicId? instrumentId,
    BusinessDate? date,
    String quantity = '10',
    String cost = '60.00',
    Currency? currency,
    int version = 1,
  }) => InvestmentHoldingLot(
    id: id ?? firstId,
    investmentAccountId: accountId ?? account.id,
    instrumentId: instrumentId ?? instrument.id,
    acquiredOn: date ?? BusinessDate(2026, 1, 1),
    remainingQuantity: ShareQuantity.parse(quantity),
    remainingCost: money(cost, currency),
    expectedVersion: version,
  );
  List<InvestmentHoldingLot> defaultLots() => [
    lot(id: secondId, date: BusinessDate(2026, 2, 1), cost: '80.00'),
    lot(id: firstId),
  ];
  InvestmentSellPreview sell({
    PublicId? id,
    OperationKey? key,
    BrokerIdentity? selectedBroker,
    InvestmentAccount? selectedAccount,
    InvestmentInstrument? selectedInstrument,
    FundingCashAccount? selectedFunding,
    InvestmentCostMethod method = InvestmentCostMethod.fifo,
    ShareQuantity? quantity,
    ShareUnitPrice? price,
    Money? gross,
    Money? fee,
    Money? tax,
    List<InvestmentHoldingLot>? lots,
  }) => InvestmentSellPreview.create(
    id: id ?? saleId,
    operation: key ?? operation,
    tradedOn: saleDate,
    broker: selectedBroker ?? broker,
    account: selectedAccount ?? account,
    instrument: selectedInstrument ?? instrument,
    funding: selectedFunding ?? funding,
    costMethod: method,
    quantity: quantity ?? ShareQuantity.parse('12'),
    unitPrice: price ?? ShareUnitPrice.parse(usd, '10'),
    executedGross: gross ?? money('120.00'),
    fee: fee ?? money('1.00'),
    tax: tax ?? money('0.50'),
    lots: lots ?? defaultLots(),
  );

  test(
    'FIFO chooses acquisition date, then ID, and preserves residual basis',
    () {
      final preview = sell();
      expect(preview.gross, money('120.00'));
      expect(preview.netCashCredit, money('118.50'));
      expect(preview.allocatedCost, money('76.00'));
      expect(preview.realizedResult, money('42.50'));
      expect(preview.allocations.map((entry) => entry.lot.id), [
        firstId,
        secondId,
      ]);
      expect(preview.allocations[0].soldQuantityUnits, units(10));
      expect(preview.allocations[0].remainingQuantityUnits, BigInt.zero);
      expect(preview.allocations[0].remainingCost, money('0'));
      expect(preview.allocations[1].soldQuantityUnits, units(2));
      expect(preview.allocations[1].allocatedSaleCost, money('16'));
      expect(preview.allocations[1].remainingQuantityUnits, units(8));
      expect(preview.allocations[1].remainingCost, money('64'));
    },
  );

  test(
    'same-date FIFO tie breaks by public lot ID, independent of input order',
    () {
      final sameDate = BusinessDate(2026, 1, 1);
      final lots = [
        lot(id: secondId, date: sameDate, cost: '80'),
        lot(id: firstId, date: sameDate, cost: '60'),
      ];
      final preview = sell(lots: lots);
      expect(preview.allocations.first.lot.id, firstId);
      expect(preview.allocations.first.soldQuantityUnits, units(10));
      preview.verifyCurrentLots(lots.reversed.toList());
      final repeated = sell(lots: lots.reversed.toList());
      expect(repeated.id, preview.id);
      expect(repeated.operation, preview.operation);
      expect(repeated.allocatedCost, preview.allocatedCost);
      expect(
        repeated.allocations.map((entry) => entry.lot.id),
        preview.allocations.map((entry) => entry.lot.id),
      );
    },
  );

  test('Average Cost uses pooled basis and rebalances remaining lot costs', () {
    final preview = sell(
      method: InvestmentCostMethod.averageCost,
      quantity: ShareQuantity.parse('5'),
      gross: money('50'),
      lots: [
        lot(cost: '100.01'),
        lot(id: secondId, cost: '200.01'),
      ],
    );
    expect(preview.allocatedCost, money('75.00'));
    expect(preview.netCashCredit, money('48.50'));
    expect(preview.realizedResult, money('-26.50'));
    expect(preview.allocations[0].soldQuantityUnits, units(5));
    expect(preview.allocations[0].remainingQuantityUnits, units(5));
    expect(preview.allocations[0].remainingCost, money('75.00'));
    expect(preview.allocations[1].soldQuantityUnits, BigInt.zero);
    expect(preview.allocations[1].remainingQuantityUnits, units(10));
    expect(preview.allocations[1].remainingCost, money('150.02'));
    expect(
      preview.allocations.fold<BigInt>(
        BigInt.zero,
        (sum, entry) => sum + entry.remainingCost.minorUnits,
      ),
      money('300.02').minorUnits - preview.allocatedCost.minorUnits,
    );
  });

  test(
    'final fractional sale consumes all residual cents under either method',
    () {
      final original = lot(quantity: '0.3', cost: '0.01');
      for (final method in InvestmentCostMethod.values) {
        final preview = sell(
          method: method,
          quantity: ShareQuantity.parse('0.3'),
          price: ShareUnitPrice.parse(usd, '1'),
          gross: money('0.30'),
          fee: money('0'),
          tax: money('0'),
          lots: [original],
        );
        expect(preview.allocatedCost, money('0.01'));
        expect(preview.allocations.single.remainingCost, money('0'));
        expect(preview.allocations.single.remainingQuantityUnits, BigInt.zero);
      }
      final partial = sell(
        quantity: ShareQuantity.parse('0.1'),
        price: ShareUnitPrice.parse(usd, '1'),
        gross: money('0.10'),
        fee: money('0'),
        tax: money('0'),
        lots: [original],
      );
      expect(partial.allocatedCost, money('0'));
      expect(partial.allocations.single.remainingCost, money('0.01'));
      final finalLot = lot(quantity: '0.2', cost: '0.01', version: 2);
      for (final method in InvestmentCostMethod.values) {
        final finalSale = sell(
          method: method,
          quantity: ShareQuantity.parse('0.2'),
          price: ShareUnitPrice.parse(usd, '1'),
          gross: money('0.20'),
          fee: money('0'),
          tax: money('0'),
          lots: [finalLot],
        );
        expect(finalSale.allocatedCost, money('0.01'));
        expect(finalSale.allocations.single.remainingCost, money('0'));
        expect(
          finalSale.allocations.single.remainingQuantityUnits,
          BigInt.zero,
        );
      }
    },
  );

  test('quote quantizes once and rejects altered executed gross', () {
    final preview = sell(
      quantity: ShareQuantity.parse('0.125'),
      price: ShareUnitPrice.parse(usd, '42.99'),
      gross: money('5.37'),
      fee: money('0'),
      tax: money('0'),
    );
    expect(preview.exactGrossNumerator, BigInt.from(537375));
    expect(preview.exactGrossDenominator, BigInt.from(100000));
    expect(preview.gross, money('5.37'));
    expect(
      InvestmentSellPreview.settlementRoundingPolicy,
      Money.roundingPolicy,
    );
    expect(
      () => sell(gross: money('120.02')),
      sellError(InvestmentSellError.grossMismatch),
    );
  });

  test(
    'rejects zero and excess sale, negative charges and nonpositive net',
    () {
      expect(
        () => ShareQuantity.parse('0'),
        throwsA(isA<InvestmentException>()),
      );
      expect(
        () => sell(quantity: ShareQuantity.parse('21'), gross: money('210')),
        sellError(InvestmentSellError.oversell),
      );
      expect(
        () => sell(fee: money('-0.01')),
        sellError(InvestmentSellError.invalidInput),
      );
      expect(
        () => sell(tax: money('-0.01')),
        sellError(InvestmentSellError.invalidInput),
      );
      expect(
        () => sell(fee: money('121')),
        sellError(InvestmentSellError.nonPositiveNet),
      );
      expect(
        () => sell(fee: money('119.50')),
        sellError(InvestmentSellError.nonPositiveNet),
      );
      expect(() => sell(lots: []), sellError(InvestmentSellError.emptyLots));
    },
  );

  test('rejects mismatched identity, currency and duplicate lot IDs', () {
    final other = PublicId.generate();
    expect(
      () => sell(lots: [lot(accountId: other)]),
      sellError(InvestmentSellError.identityMismatch),
    );
    expect(
      () => sell(lots: [lot(instrumentId: other)]),
      sellError(InvestmentSellError.identityMismatch),
    );
    expect(
      () => sell(lots: [lot(date: BusinessDate(2026, 10, 1))]),
      sellError(InvestmentSellError.identityMismatch),
    );
    expect(
      () => sell(lots: [lot(currency: eur)]),
      sellError(InvestmentSellError.currencyMismatch),
    );
    expect(
      () => sell(fee: money('1', eur)),
      sellError(InvestmentSellError.currencyMismatch),
    );
    expect(
      () => sell(lots: [lot(), lot()]),
      sellError(InvestmentSellError.duplicateIdentity),
    );
    expect(
      () => sell(id: firstId),
      sellError(InvestmentSellError.duplicateIdentity),
    );
  });

  test('rejects mismatched workspace, broker and linked cash account', () {
    expect(
      () => sell(
        key: OperationKey(
          WorkspaceId(PublicId.generate()),
          OperationId(PublicId.generate()),
        ),
      ),
      sellError(InvestmentSellError.workspaceMismatch),
    );
    expect(
      () => sell(
        selectedBroker: BrokerIdentity(
          id: PublicId.generate(),
          workspace: workspace,
          name: 'Other broker',
        ),
      ),
      sellError(InvestmentSellError.brokerMismatch),
    );
    expect(
      () => sell(
        selectedFunding: FundingCashAccount(
          id: PublicId.generate(),
          workspace: workspace,
          currency: usd,
          expectedVersion: 1,
        ),
      ),
      sellError(InvestmentSellError.fundingAccountMismatch),
    );
  });

  test(
    'commit-time snapshot check rejects version, value, missing and extra lots',
    () {
      final preview = sell();
      expect(
        () => preview.verifyCurrentLots([lot(version: 2), defaultLots().first]),
        sellError(InvestmentSellError.staleLots),
      );
      expect(
        () => preview.verifyCurrentLots([
          lot(cost: '59.99'),
          defaultLots().first,
        ]),
        sellError(InvestmentSellError.staleLots),
      );
      expect(
        () => preview.verifyCurrentLots([
          lot(quantity: '9'),
          defaultLots().first,
        ]),
        sellError(InvestmentSellError.staleLots),
      );
      expect(
        () => preview.verifyCurrentLots([lot()]),
        sellError(InvestmentSellError.staleLots),
      );
      expect(
        () => preview.verifyCurrentLots([
          ...defaultLots(),
          lot(id: PublicId.generate()),
        ]),
        sellError(InvestmentSellError.staleLots),
      );
    },
  );

  test('rejects signed money overflow before proposing sale', () {
    expect(
      () => sell(
        quantity: ShareQuantity.parse('1'),
        price: ShareUnitPrice.parse(usd, '92233720368547758.08'),
        gross: Money(usd, Money.maxMinorUnits),
      ),
      sellError(InvestmentSellError.overflow),
    );
    expect(
      () => sell(
        quantity: ShareQuantity.parse('1'),
        price: ShareUnitPrice.parse(usd, '1'),
        gross: money('1'),
        fee: money('0'),
        tax: money('0'),
        lots: [
          lot(cost: '92233720368547758.07'),
          lot(id: secondId, cost: '0.01'),
        ],
      ),
      sellError(InvestmentSellError.overflow),
    );
  });
}
