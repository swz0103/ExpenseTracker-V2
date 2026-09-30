import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:test/test.dart';

void main() {
  const codec = InvestmentSellPreviewCodec();
  final workspace = WorkspaceId(PublicId.generate());
  final currency = Currency('USD', 2);
  final brokerId = PublicId.generate();
  final fundingId = PublicId.generate();
  final accountId = PublicId.generate();
  final instrumentId = PublicId.generate();
  final sellId = PublicId.generate();
  final operationId = OperationId(PublicId.generate());
  final firstId = PublicId.generate();
  final secondId = PublicId.generate();

  List<InvestmentHoldingLot> lots() => [
    InvestmentHoldingLot(
      id: secondId,
      investmentAccountId: accountId,
      instrumentId: instrumentId,
      acquiredOn: BusinessDate(2026, 2, 1),
      remainingQuantity: ShareQuantity.parse('1.3750'),
      remainingCost: Money.parse(currency, '20.01'),
      expectedVersion: 3,
    ),
    InvestmentHoldingLot(
      id: firstId,
      investmentAccountId: accountId,
      instrumentId: instrumentId,
      acquiredOn: BusinessDate(2026, 1, 1),
      remainingQuantity: ShareQuantity.parse('1.0000'),
      remainingCost: Money.parse(currency, '10.01'),
      expectedVersion: 7,
    ),
  ];

  InvestmentSellPreview intent({
    InvestmentCostMethod method = InvestmentCostMethod.averageCost,
    List<InvestmentHoldingLot>? holdings,
  }) => InvestmentSellPreview.create(
    id: sellId,
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
      expectedVersion: 5,
    ),
    costMethod: method,
    quantity: ShareQuantity.parse('0.1250'),
    unitPrice: ShareUnitPrice.parse(currency, '42.990'),
    executedGross: Money.parse(currency, '5.37'),
    fee: Money.parse(currency, '0.03'),
    tax: Money.parse(currency, '0.02'),
    lots: holdings ?? lots(),
  );

  String changed(String encoded, String key, Object? replacement) {
    final map = jsonDecode(encoded) as Map<String, dynamic>;
    map[key] = replacement;
    return jsonEncode(map);
  }

  String changedLot(
    String encoded,
    int index,
    String key,
    Object? replacement,
  ) {
    final map = jsonDecode(encoded) as Map<String, dynamic>;
    final entries = map['lots'] as List<dynamic>;
    (entries[index] as Map<String, dynamic>)[key] = replacement;
    return jsonEncode(map);
  }

  test(
    'round trip retains fixed retry IDs, identities and every lot snapshot',
    () {
      for (final method in InvestmentCostMethod.values) {
        final input = intent(method: method);
        final encoded = codec.encode(input);
        final decoded = codec.decode(encoded);
        expect(codec.encode(decoded), encoded);
        expect(decoded.sellId, sellId);
        expect(decoded.operation, OperationKey(workspace, operationId));
        expect(decoded.tradedOn, BusinessDate(2026, 9, 30));
        expect(decoded.broker.id, brokerId);
        expect(decoded.broker.name, 'Synthetic broker');
        expect(decoded.account.id, accountId);
        expect(decoded.account.expectedVersion, 4);
        expect(decoded.account.fundingCashAccountId, fundingId);
        expect(decoded.funding.id, fundingId);
        expect(decoded.funding.expectedVersion, 5);
        expect(decoded.instrument.id, instrumentId);
        expect(decoded.instrument.kind, InstrumentKind.etf);
        expect(decoded.instrument.marketCode, 'XNAS');
        expect(decoded.instrument.symbol, 'SYN.ETF');
        expect(decoded.instrument.tradingCurrency, currency);
        expect(decoded.costMethod, method);
        expect(decoded.quantity.toString(), '0.1250');
        expect(decoded.unitPrice.toString(), '42.990');
        expect(decoded.gross, Money.parse(currency, '5.37'));
        expect(decoded.fee, Money.parse(currency, '0.03'));
        expect(decoded.tax, Money.parse(currency, '0.02'));
        expect(decoded.cashCredit, input.cashCredit);
        expect(decoded.allocatedCost, input.allocatedCost);
        expect(decoded.realizedResult, input.realizedResult);
        expect(decoded.exactGrossNumerator, input.exactGrossNumerator);
        expect(decoded.exactGrossDenominator, input.exactGrossDenominator);
        expect(decoded.allocations.map((item) => item.lot.id), [
          firstId,
          secondId,
        ]);
        expect(
          decoded.allocations.first.lot.remainingQuantity.toString(),
          '1.0000',
        );
        expect(
          decoded.allocations.first.lot.remainingCost,
          Money.parse(currency, '10.01'),
        );
        expect(decoded.allocations.first.lot.expectedVersion, 7);
        expect(
          decoded.allocations.last.lot.remainingQuantity.toString(),
          '1.3750',
        );
        expect(
          decoded.allocations.last.lot.remainingCost,
          Money.parse(currency, '20.01'),
        );
        expect(decoded.allocations.last.lot.expectedVersion, 3);
        decoded.verifyCurrentLots(lots());
      }
    },
  );

  test(
    'rejects unknown format, missing or extra fields, and reordered JSON',
    () {
      final encoded = codec.encode(intent());
      expect(
        () => codec.decode(changed(encoded, 'format', 2)),
        throwsFormatException,
      );
      expect(
        () => codec.decode(changed(encoded, 'extra', true)),
        throwsFormatException,
      );
      final missing = jsonDecode(encoded) as Map<String, dynamic>;
      missing.remove('feeMinor');
      expect(() => codec.decode(jsonEncode(missing)), throwsFormatException);
      expect(() => codec.decode(' $encoded'), throwsFormatException);
      final reordered = jsonDecode(encoded) as Map<String, dynamic>;
      final format = reordered.remove('format');
      reordered['format'] = format;
      expect(() => codec.decode(jsonEncode(reordered)), throwsFormatException);
      final reversedLots = jsonDecode(encoded) as Map<String, dynamic>;
      reversedLots['lots'] = (reversedLots['lots'] as List<dynamic>).reversed
          .toList();
      expect(
        () => codec.decode(jsonEncode(reversedLots)),
        throwsFormatException,
      );
    },
  );

  test('recalculates settlement and basis; rejects inconsistent amounts', () {
    final encoded = codec.encode(intent());
    for (final (key, value) in <(String, Object?)>[
      ('grossMinor', '538'),
      ('feeMinor', '-1'),
      ('cashCreditMinor', '533'),
      ('allocatedCostMinor', '999'),
      ('realizedResultMinor', '999'),
      ('quantity', '0.1260'),
      ('unitPrice', '43.000'),
      ('roundingPolicy', 'other'),
      ('basisAllocationPolicy', 'other'),
      ('costMethod', 'unknown'),
    ]) {
      expect(
        () => codec.decode(changed(encoded, key, value)),
        throwsFormatException,
        reason: key,
      );
    }
    expect(
      () => codec.decode(changedLot(encoded, 0, 'remainingCostMinor', '-1')),
      throwsFormatException,
    );
    expect(
      () => codec.decode(changedLot(encoded, 0, 'remainingQuantity', '0')),
      throwsFormatException,
    );
  });

  test('rejects malformed lot identities, dates, versions and field types', () {
    final encoded = codec.encode(intent());
    for (final (key, value) in <(String, Object?)>[
      ('investmentAccountId', PublicId.generate().value),
      ('instrumentId', PublicId.generate().value),
      ('acquiredOn', '2026-02-30'),
      ('expectedVersion', 0),
      ('remainingCostMinor', '01'),
      ('remainingQuantity', 1.5),
    ]) {
      expect(
        () => codec.decode(changedLot(encoded, 0, key, value)),
        throwsFormatException,
        reason: key,
      );
    }
    final extra = jsonDecode(encoded) as Map<String, dynamic>;
    ((extra['lots'] as List<dynamic>)[0] as Map<String, dynamic>)['extra'] = 1;
    expect(() => codec.decode(jsonEncode(extra)), throwsFormatException);
    expect(
      () => codec.decode(changedLot(encoded, 1, 'id', firstId.value)),
      throwsFormatException,
    );
  });

  test(
    'rejects noncanonical IDs, money text, wrong types and oversize bytes',
    () {
      final encoded = codec.encode(intent());
      expect(
        () => codec.decode(
          changed(encoded, 'sellId', sellId.value.toUpperCase()),
        ),
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
        () => codec.decode(changed(encoded, 'fundingAccountVersion', '5')),
        throwsFormatException,
      );
      expect(
        () => codec.decode('x' * (InvestmentSellPreviewCodec.maxBytes + 1)),
        throwsFormatException,
      );
      expect(() => codec.decode('not json'), throwsFormatException);
    },
  );

  test(
    'vault bytes bound fails closed when a large position cannot be retained',
    () {
      final many = <InvestmentHoldingLot>[
        for (var index = 0; index < 1100; index++)
          InvestmentHoldingLot(
            id: PublicId.generate(),
            investmentAccountId: accountId,
            instrumentId: instrumentId,
            acquiredOn: BusinessDate(2026, 1, 1),
            remainingQuantity: ShareQuantity.parse('1'),
            remainingCost: Money.parse(currency, '1'),
            expectedVersion: 1,
          ),
      ];
      expect(() => codec.encode(intent(holdings: many)), throwsFormatException);
    },
  );

  test(
    'versions are retry snapshots, then authoritative lots still decide',
    () {
      final encoded = codec.encode(intent());
      final changedVersion = changedLot(encoded, 0, 'expectedVersion', 8);
      final decoded = codec.decode(changedVersion);
      expect(decoded.allocations.first.lot.expectedVersion, 8);
      expect(
        () => decoded.verifyCurrentLots(lots()),
        throwsA(isA<InvestmentSellException>()),
      );
    },
  );
}
