import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  const codec = StockSplitPreviewCodec();
  final workspace = WorkspaceId(PublicId.generate());
  final currency = Currency('USD', 2);
  final broker = BrokerIdentity(
    id: PublicId.generate(),
    workspace: workspace,
    name: 'Synthetic broker',
  );
  final fundingId = PublicId.generate();
  final account = InvestmentAccount(
    id: PublicId.generate(),
    workspace: workspace,
    brokerId: broker.id,
    fundingCashAccountId: fundingId,
    name: 'Synthetic portfolio',
    expectedVersion: 1,
  );
  final instrument = InvestmentInstrument(
    id: PublicId.generate(),
    kind: InstrumentKind.stock,
    marketCode: 'XNAS',
    symbol: 'SYN',
    name: 'Synthetic stock',
    tradingCurrency: currency,
  );
  final lotId = PublicId.generate();
  final splitId = PublicId.generate();
  final operationId = OperationId(PublicId.generate());

  StockSplitPreview preview() => StockSplitPreview.create(
    id: splitId,
    operation: OperationKey(workspace, operationId),
    effectiveOn: BusinessDate(2028, 3, 15),
    broker: broker,
    account: account,
    instrument: instrument,
    newShares: 3,
    oldShares: 2,
    lots: [
      InvestmentHoldingLot(
        id: lotId,
        investmentAccountId: account.id,
        instrumentId: instrument.id,
        acquiredOn: BusinessDate(2028, 2, 20),
        remainingQuantity: ShareQuantity.parse('1.5'),
        remainingCost: Money.parse(currency, '21'),
        expectedVersion: 2,
      ),
    ],
  );

  String changed(String encoded, String key, Object value) {
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    data[key] = value;
    return jsonEncode(data);
  }

  test(
    'canonical round trip preserves fixed ID, lot version and exact cost',
    () {
      final encoded = codec.encode(preview());
      final restored = codec.decode(encoded);
      expect(codec.encode(restored), encoded);
      expect(restored.id, splitId);
      expect(restored.operation, OperationKey(workspace, operationId));
      expect(restored.lots.single.before.expectedVersion, 2);
      expect(restored.lots.single.before.remainingCost.majorText, '21.00');
      expect(restored.lots.single.afterQuantity.toString(), '2.25');
    },
  );

  test('rejects version, identity, ratio, lot and canonical tampering', () {
    final encoded = codec.encode(preview());
    for (final (key, value) in <(String, Object)>[
      ('format', 2),
      ('newShares', 1),
      ('effectiveOn', '2028-02-19'),
      ('splitId', splitId.value.toUpperCase()),
      ('extra', 1),
    ]) {
      expect(
        () => codec.decode(changed(encoded, key, value)),
        throwsFormatException,
        reason: key,
      );
    }
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    final lots = data['lots'] as List;
    (lots.single as Map<String, dynamic>)['remainingCostMinor'] = '-1';
    expect(() => codec.decode(jsonEncode(data)), throwsFormatException);
    expect(() => codec.decode(' $encoded'), throwsFormatException);
    expect(
      () => codec.decode('x' * (StockSplitPreviewCodec.maxBytes + 1)),
      throwsFormatException,
    );
  });
}
