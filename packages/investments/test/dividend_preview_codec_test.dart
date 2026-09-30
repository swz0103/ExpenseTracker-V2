import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  const codec = InvestmentDividendPreviewCodec();
  final workspace = WorkspaceId(PublicId.generate());
  final usd = Currency('USD', 2);
  final brokerId = PublicId.generate();
  final accountId = PublicId.generate();
  final instrumentId = PublicId.generate();
  final fundingId = PublicId.generate();
  final dividendId = PublicId.generate();
  final operationId = OperationId(PublicId.generate());

  InvestmentDividendPreview intent() => InvestmentDividendPreview.create(
    id: dividendId,
    operation: OperationKey(workspace, operationId),
    paidOn: BusinessDate(2028, 3, 15),
    broker: BrokerIdentity(
      id: brokerId,
      workspace: workspace,
      name: 'Synthetic broker',
    ),
    account: InvestmentAccount(
      id: accountId,
      workspace: workspace,
      brokerId: brokerId,
      fundingCashAccountId: fundingId,
      name: 'Synthetic portfolio',
      expectedVersion: 2,
    ),
    instrument: InvestmentInstrument(
      id: instrumentId,
      kind: InstrumentKind.etf,
      marketCode: 'XNAS',
      symbol: 'SYN',
      name: 'Synthetic ETF',
      tradingCurrency: usd,
    ),
    funding: FundingCashAccount(
      id: fundingId,
      workspace: workspace,
      currency: usd,
      expectedVersion: 3,
    ),
    gross: Money.parse(usd, '10.00'),
    withholdingTax: Money.parse(usd, '1.50'),
    fee: Money.parse(usd, '0.25'),
    reportedNet: Money.parse(usd, '8.25'),
  );

  String changed(String encoded, String key, Object? replacement) {
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    data[key] = replacement;
    return jsonEncode(data);
  }

  test('canonical round trip keeps fixed operation and exact cash amounts', () {
    final encoded = codec.encode(intent());
    final restored = codec.decode(encoded);
    expect(codec.encode(restored), encoded);
    expect(restored.id, dividendId);
    expect(restored.operation, OperationKey(workspace, operationId));
    expect(restored.paidOn, BusinessDate(2028, 3, 15));
    expect(restored.account.expectedVersion, 2);
    expect(restored.funding.expectedVersion, 3);
    expect(restored.instrument.id, instrumentId);
    expect(restored.gross, Money.parse(usd, '10.00'));
    expect(restored.withholdingTax, Money.parse(usd, '1.50'));
    expect(restored.fee, Money.parse(usd, '0.25'));
    expect(restored.netCashCredit, Money.parse(usd, '8.25'));
  });

  test('rejects altered net, invalid fees, versions and canonical form', () {
    final encoded = codec.encode(intent());
    for (final (key, value) in <(String, Object?)>[
      ('format', 2),
      ('netCashCreditMinor', '826'),
      ('withholdingTaxMinor', '-1'),
      ('feeMinor', '025'),
      ('fundingAccountVersion', 0),
      ('paidOn', '2028-02-30'),
      ('dividendId', dividendId.value.toUpperCase()),
      ('grossMinor', 1000),
      ('extra', 1),
    ]) {
      expect(
        () => codec.decode(changed(encoded, key, value)),
        throwsFormatException,
        reason: key,
      );
    }
    expect(() => codec.decode(' $encoded'), throwsFormatException);
    expect(
      () => codec.decode('x' * (InvestmentDividendPreviewCodec.maxBytes + 1)),
      throwsFormatException,
    );
  });
}
