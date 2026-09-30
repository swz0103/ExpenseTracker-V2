import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2);
  final broker = BrokerIdentity(
    id: PublicId.generate(),
    workspace: workspace,
    name: 'Synthetic broker',
  );
  final account = InvestmentAccount(
    id: PublicId.generate(),
    workspace: workspace,
    brokerId: broker.id,
    fundingCashAccountId: PublicId.generate(),
    name: 'Synthetic portfolio',
    expectedVersion: 1,
  );
  final stock = InvestmentInstrument(
    id: PublicId.generate(),
    kind: InstrumentKind.stock,
    marketCode: 'XNAS',
    symbol: 'TEST',
    name: 'Synthetic stock',
    tradingCurrency: usd,
  );
  final firstId = PublicId.generate();
  final secondId = PublicId.generate();

  InvestmentHoldingLot lot({
    required PublicId id,
    String quantity = '2.5',
    String cost = '12.34',
    PublicId? accountId,
    PublicId? instrumentId,
    BusinessDate? acquiredOn,
    int version = 1,
  }) => InvestmentHoldingLot(
    id: id,
    investmentAccountId: accountId ?? account.id,
    instrumentId: instrumentId ?? stock.id,
    acquiredOn: acquiredOn ?? BusinessDate(2026, 1, 1),
    remainingQuantity: ShareQuantity.parse(quantity),
    remainingCost: Money.parse(usd, cost),
    expectedVersion: version,
  );

  StockSplitPreview preview({
    int newShares = 2,
    int oldShares = 1,
    List<InvestmentHoldingLot>? lots,
    OperationKey? operation,
    BusinessDate? effectiveOn,
    PublicId? id,
  }) => StockSplitPreview.create(
    id: id ?? PublicId.generate(),
    operation:
        operation ?? OperationKey(workspace, OperationId(PublicId.generate())),
    effectiveOn: effectiveOn ?? BusinessDate(2026, 9, 30),
    broker: broker,
    account: account,
    instrument: stock,
    newShares: newShares,
    oldShares: oldShares,
    lots:
        lots ??
        [
          lot(
            id: secondId,
            quantity: '1',
            cost: '9.99',
            acquiredOn: BusinessDate(2026, 2, 1),
          ),
          lot(id: firstId),
        ],
  );

  Matcher splitError(StockSplitError code) =>
      throwsA(isA<StockSplitException>().having((e) => e.code, 'code', code));

  test('2-for-1 changes every lot quantity without changing any cost', () {
    final result = preview();
    expect(result.lots.map((row) => row.afterQuantity.toString()), ['5', '2']);
    expect(result.lots.map((row) => row.cost.minorUnits), [
      BigInt.from(1234),
      BigInt.from(999),
    ]);
    expect(result.lots.map((row) => row.before.id), [firstId, secondId]);
    result.verifyCurrentLots(
      result.lots.reversed.map((row) => row.before).toList(),
    );
  });

  test('3-for-2 preserves exact fractional shares and rejects rounding', () {
    final exact = preview(
      newShares: 3,
      oldShares: 2,
      lots: [lot(id: firstId, quantity: '0.125')],
    );
    expect(exact.lots.single.afterQuantity, ShareQuantity.parse('0.1875'));
    expect(
      () => preview(
        newShares: 3,
        oldShares: 2,
        lots: [lot(id: firstId, quantity: '0.000000000001')],
      ),
      splitError(StockSplitError.fractionalPrecision),
    );
  });

  test(
    'rejects reverse/no-op ratio, empty lots, duplicate lots and future lot',
    () {
      expect(
        () => preview(newShares: 1),
        splitError(StockSplitError.invalidRatio),
      );
      expect(
        () => preview(newShares: 1, oldShares: 2),
        splitError(StockSplitError.invalidRatio),
      );
      expect(() => preview(lots: []), splitError(StockSplitError.emptyLots));
      expect(
        () => preview(
          lots: [
            lot(id: firstId),
            lot(id: firstId),
          ],
        ),
        splitError(StockSplitError.duplicateLot),
      );
      expect(
        () => preview(
          lots: [lot(id: firstId, acquiredOn: BusinessDate(2026, 10, 1))],
        ),
        splitError(StockSplitError.invalidDate),
      );
    },
  );

  test('checks identity and rejects changed holdings before a commit', () {
    expect(
      () => preview(
        lots: [lot(id: firstId, accountId: PublicId.generate())],
      ),
      splitError(StockSplitError.identityMismatch),
    );
    expect(
      () => preview(
        operation: OperationKey(
          WorkspaceId(PublicId.generate()),
          OperationId(PublicId.generate()),
        ),
      ),
      splitError(StockSplitError.workspaceMismatch),
    );
    final result = preview(lots: [lot(id: firstId)]);
    expect(
      () => result.verifyCurrentLots([lot(id: firstId, version: 2)]),
      splitError(StockSplitError.staleLots),
    );
    expect(
      () => result.verifyCurrentLots([lot(id: firstId, cost: '12.35')]),
      splitError(StockSplitError.staleLots),
    );
    expect(
      () => result.verifyCurrentLots([]),
      splitError(StockSplitError.staleLots),
    );
  });
}
