import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  final workspace = WorkspaceId(PublicId.generate());
  final twd = Currency.of('TWD');
  Money ntd(int units) => Money(twd, BigInt.from(units));
  final account = InvestmentAccount(
    id: PublicId.generate(),
    workspace: workspace,
    brokerId: PublicId.generate(),
    fundingCashAccountId: PublicId.generate(),
    name: 'Synthetic account',
    expectedVersion: 1,
  );
  final listed = InvestmentInstrument(
    id: PublicId.generate(),
    kind: InstrumentKind.stock,
    marketCode: 'TWSE',
    symbol: '9999',
    name: 'Synthetic stock',
    tradingCurrency: twd,
  );
  InvestmentHoldingLot lot(String shares, int cost, int month) =>
      InvestmentHoldingLot(
        id: PublicId.generate(),
        investmentAccountId: account.id,
        instrumentId: listed.id,
        acquiredOn: BusinessDate(2026, month, 1),
        remainingQuantity: ShareQuantity.parse(shares),
        remainingCost: ntd(cost),
        expectedVersion: 1,
      );
  final older = lot('1000', 50000, 1);
  final newer = lot('234', 12000, 2);
  CorporateActionPreview action({
    required int newShares,
    required int oldShares,
    Money? inLieu,
    Money? returned,
    InvestmentInstrument? instrument,
  }) => CorporateActionPreview.create(
    id: PublicId.generate(),
    operation: OperationKey(workspace, OperationId(PublicId.generate())),
    effectiveOn: BusinessDate(2026, 9, 1),
    account: account,
    instrument: instrument ?? listed,
    newShares: newShares,
    oldShares: oldShares,
    lots: [newer, older],
    cashInLieu: inLieu,
    capitalReturned: returned,
  );
  BigInt shares(int whole) => BigInt.from(whole) * BigInt.from(10).pow(12);

  test('a capital reduction drops the fraction and returns capital', () {
    final preview = action(
      newShares: 600,
      oldShares: 1000,
      inLieu: ntd(20),
      returned: ntd(4936),
    );
    final first = preview.lots.first;
    final second = preview.lots.last;
    expect(first.before.id, older.id);
    expect(first.afterUnits, shares(600));
    expect(second.afterUnits, shares(140));
    // 0.4 of 140.4 shares cost 34; the basis then falls by 4,936 in
    // proportion to cost.
    expect(first.afterCost, ntd(50000 - 3983));
    expect(second.afterCost, ntd(12000 - 34 - 953));
    expect(preview.cash, ntd(4956));
    expect(preview.realized, ntd(20 - 34));
  });

  test('a stock dividend adds shares at no cost', () {
    final preview = action(newShares: 1050, oldShares: 1000, inLieu: ntd(9));
    expect(preview.lots.first.afterUnits, shares(1050));
    // 245.7 shares: 0.7 is paid in cash.
    expect(preview.lots.last.afterUnits, shares(245));
    expect(preview.lots.first.afterCost, ntd(50000));
    expect(preview.cash, ntd(9));
  });

  test('returned capital beyond the basis is a gain', () {
    final preview = action(newShares: 1, oldShares: 1, returned: ntd(70000));
    expect(preview.lots.first.afterCost, ntd(0));
    expect(preview.lots.last.afterCost, ntd(0));
    expect(preview.realized, ntd(8000));
  });

  test('cash in lieu needs a fraction, and ratios must be positive', () {
    expect(
      () => action(newShares: 2, oldShares: 1, inLieu: ntd(1)),
      throwsA(isA<InvestmentException>()),
    );
    expect(
      () => action(newShares: 0, oldShares: 1),
      throwsA(isA<StockSplitException>()),
    );
  });
}
