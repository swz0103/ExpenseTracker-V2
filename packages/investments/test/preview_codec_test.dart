import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  const codec = InvestmentBuyPreviewCodec();
  final workspace = WorkspaceId(PublicId.generate());
  final currency = Currency('USD', 2);
  final brokerId = PublicId.generate();
  final fundingId = PublicId.generate();
  final accountId = PublicId.generate();
  final instrumentId = PublicId.generate();
  final buyId = PublicId.generate();
  final lotId = PublicId.generate();
  final operationId = OperationId(PublicId.generate());

  InvestmentBuyPreview intent() => InvestmentBuyPreview.create(
    id: buyId,
    lotId: lotId,
    operation: OperationKey(workspace, operationId),
    tradedOn: BusinessDate(2026, 9, 30),
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
      expectedVersion: 4,
    ),
    instrument: InvestmentInstrument(
      id: instrumentId,
      kind: InstrumentKind.etf,
      marketCode: 'XNAS',
      symbol: 'SYN.ETF',
      name: 'Synthetic ETF',
      tradingCurrency: currency,
    ),
    funding: FundingCashAccount(
      id: fundingId,
      workspace: workspace,
      currency: currency,
      expectedVersion: 7,
    ),
    quantity: ShareQuantity.parse('0.1250'),
    unitPrice: ShareUnitPrice.parse(currency, '42.990'),
    executedGross: Money.parse(currency, '5.37'),
    fee: Money.parse(currency, '0.03'),
    tax: Money.parse(currency, '0.02'),
  );

  String changed(String encoded, String key, Object? replacement) {
    final map = jsonDecode(encoded) as Map<String, dynamic>;
    map[key] = replacement;
    return jsonEncode(map);
  }

  test('round trip keeps every durable identity and exact financial value', () {
    final input = intent();
    final encoded = codec.encode(input);
    final decoded = codec.decode(encoded);
    expect(codec.encode(decoded), encoded);
    expect(decoded.id, buyId);
    expect(decoded.lot.id, lotId);
    expect(decoded.operation, OperationKey(workspace, operationId));
    expect(decoded.tradedOn, BusinessDate(2026, 9, 30));
    expect(decoded.broker.id, brokerId);
    expect(decoded.broker.name, input.broker.name);
    expect(decoded.account.id, accountId);
    expect(decoded.account.expectedVersion, 4);
    expect(decoded.account.fundingCashAccountId, fundingId);
    expect(decoded.funding.id, fundingId);
    expect(decoded.funding.expectedVersion, 7);
    expect(decoded.instrument.id, instrumentId);
    expect(decoded.instrument.kind, InstrumentKind.etf);
    expect(decoded.instrument.marketCode, 'XNAS');
    expect(decoded.instrument.symbol, 'SYN.ETF');
    expect(decoded.instrument.tradingCurrency, currency);
    expect(decoded.quantity.toString(), '0.1250');
    expect(decoded.unitPrice.toString(), '42.990');
    expect(decoded.gross, Money.parse(currency, '5.37'));
    expect(decoded.fee, Money.parse(currency, '0.03'));
    expect(decoded.tax, Money.parse(currency, '0.02'));
    expect(decoded.cashDebit, Money.parse(currency, '5.42'));
    expect(decoded.lot.acquisitionCashCost, decoded.cashDebit);
    expect(decoded.exactGrossNumerator, input.exactGrossNumerator);
    expect(decoded.exactGrossDenominator, input.exactGrossDenominator);
  });

  test('rejects unknown version, extra fields and noncanonical JSON', () {
    final encoded = codec.encode(intent());
    expect(
      () => codec.decode(changed(encoded, 'format', 2)),
      throwsFormatException,
    );
    expect(
      () => codec.decode(changed(encoded, 'unexpected', true)),
      throwsFormatException,
    );
    expect(() => codec.decode(' $encoded'), throwsFormatException);
    final reordered = jsonDecode(encoded) as Map<String, dynamic>;
    final first = reordered.remove('format');
    reordered['format'] = first;
    expect(() => codec.decode(jsonEncode(reordered)), throwsFormatException);
  });

  test('rejects altered financial components or identity linkage', () {
    final encoded = codec.encode(intent());
    for (final (key, value) in <(String, Object?)>[
      ('grossMinor', '538'),
      ('feeMinor', '-1'),
      ('cashDebitMinor', '543'),
      ('roundingPolicy', 'other'),
      ('lotId', buyId.value),
      ('fundingAccountVersion', 0),
      ('quantity', '0.1260'),
      ('unitPrice', '43.000'),
      ('tradedOn', '2026-02-30'),
      ('currencyScale', 3),
    ]) {
      expect(
        () => codec.decode(changed(encoded, key, value)),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test('rejects noncanonical IDs, money text, types and oversize input', () {
    final encoded = codec.encode(intent());
    expect(
      () => codec.decode(changed(encoded, 'buyId', buyId.value.toUpperCase())),
      throwsFormatException,
    );
    expect(
      () => codec.decode(changed(encoded, 'feeMinor', '03')),
      throwsFormatException,
    );
    expect(
      () => codec.decode(changed(encoded, 'feeMinor', 3)),
      throwsFormatException,
    );
    expect(
      () => codec.decode(changed(encoded, 'investmentAccountVersion', '4')),
      throwsFormatException,
    );
    expect(() => codec.decode('x' * 4097), throwsFormatException);
  });
}
