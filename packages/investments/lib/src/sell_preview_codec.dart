import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';

import 'buy.dart';
import 'sell.dart';

/// Canonical retry intent for a private vault. This is not an authenticated
/// backup or proof that the referenced account and lots remain current.
final class InvestmentSellPreviewCodec {
  const InvestmentSellPreviewCodec();

  static const formatVersion = 1;

  /// The sale row and operation receipt each have a 1 MiB Ledger limit. Their
  /// nested JSON escaping is larger than this intent, so fail closed early.
  static const maxBytes = 256 * 1024;

  static const _keys = {
    'format',
    'sellId',
    'workspace',
    'operationId',
    'tradedOn',
    'brokerId',
    'brokerName',
    'investmentAccountId',
    'investmentAccountName',
    'investmentAccountVersion',
    'fundingAccountId',
    'fundingAccountVersion',
    'instrumentId',
    'instrumentKind',
    'marketCode',
    'symbol',
    'instrumentName',
    'currency',
    'currencyScale',
    'costMethod',
    'quantity',
    'unitPrice',
    'grossMinor',
    'feeMinor',
    'taxMinor',
    'cashCreditMinor',
    'allocatedCostMinor',
    'realizedResultMinor',
    'roundingPolicy',
    'basisAllocationPolicy',
    'lots',
  };
  static const _lotKeys = {
    'id',
    'investmentAccountId',
    'instrumentId',
    'acquiredOn',
    'remainingQuantity',
    'remainingCostMinor',
    'expectedVersion',
  };

  String encode(InvestmentSellPreview preview) {
    final value = jsonEncode({
      'format': formatVersion,
      'sellId': preview.sellId.value,
      'workspace': preview.operation.workspace.id.value,
      'operationId': preview.operation.operation.id.value,
      'tradedOn': preview.tradedOn.toString(),
      'brokerId': preview.broker.id.value,
      'brokerName': preview.broker.name,
      'investmentAccountId': preview.account.id.value,
      'investmentAccountName': preview.account.name,
      'investmentAccountVersion': preview.account.expectedVersion,
      'fundingAccountId': preview.funding.id.value,
      'fundingAccountVersion': preview.funding.expectedVersion,
      'instrumentId': preview.instrument.id.value,
      'instrumentKind': preview.instrument.kind.name,
      'marketCode': preview.instrument.marketCode,
      'symbol': preview.instrument.symbol,
      'instrumentName': preview.instrument.name,
      'currency': preview.instrument.tradingCurrency.code,
      'currencyScale': preview.instrument.tradingCurrency.scale,
      'costMethod': preview.costMethod.name,
      'quantity': preview.quantity.toString(),
      'unitPrice': preview.unitPrice.toString(),
      'grossMinor': preview.gross.minorUnits.toString(),
      'feeMinor': preview.fee.minorUnits.toString(),
      'taxMinor': preview.tax.minorUnits.toString(),
      'cashCreditMinor': preview.cashCredit.minorUnits.toString(),
      'allocatedCostMinor': preview.allocatedCost.minorUnits.toString(),
      'realizedResultMinor': preview.realizedResult.minorUnits.toString(),
      'roundingPolicy': InvestmentSellPreview.settlementRoundingPolicy,
      'basisAllocationPolicy': InvestmentSellPreview.basisAllocationPolicy,
      'lots': [
        for (final allocation in preview.allocations)
          {
            'id': allocation.lot.id.value,
            'investmentAccountId': allocation.lot.investmentAccountId.value,
            'instrumentId': allocation.lot.instrumentId.value,
            'acquiredOn': allocation.lot.acquiredOn.toString(),
            'remainingQuantity': allocation.lot.remainingQuantity.toString(),
            'remainingCostMinor': allocation.lot.remainingCost.minorUnits
                .toString(),
            'expectedVersion': allocation.lot.expectedVersion,
          },
      ],
    });
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Investment sale intent exceeds size limit');
    }
    return value;
  }

  InvestmentSellPreview decode(String value) {
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Investment sale intent exceeds size limit');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw const FormatException('Invalid investment sale intent JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        !_exactKeys(decoded, _keys) ||
        decoded['format'] != formatVersion ||
        decoded['roundingPolicy'] !=
            InvestmentSellPreview.settlementRoundingPolicy ||
        decoded['basisAllocationPolicy'] !=
            InvestmentSellPreview.basisAllocationPolicy) {
      throw const FormatException('Invalid investment sale intent fields');
    }
    try {
      final workspace = WorkspaceId.parse(_string(decoded, 'workspace'));
      final currency = Currency(
        _string(decoded, 'currency'),
        _integer(decoded, 'currencyScale'),
      );
      final broker = BrokerIdentity(
        id: PublicId.parse(_string(decoded, 'brokerId')),
        workspace: workspace,
        name: _string(decoded, 'brokerName'),
      );
      final fundingId = PublicId.parse(_string(decoded, 'fundingAccountId'));
      final account = InvestmentAccount(
        id: PublicId.parse(_string(decoded, 'investmentAccountId')),
        workspace: workspace,
        brokerId: broker.id,
        fundingCashAccountId: fundingId,
        name: _string(decoded, 'investmentAccountName'),
        expectedVersion: _integer(decoded, 'investmentAccountVersion'),
      );
      final instrument = InvestmentInstrument(
        id: PublicId.parse(_string(decoded, 'instrumentId')),
        kind: switch (_string(decoded, 'instrumentKind')) {
          'stock' => InstrumentKind.stock,
          'etf' => InstrumentKind.etf,
          _ => throw const FormatException('Invalid instrument kind'),
        },
        marketCode: _string(decoded, 'marketCode'),
        symbol: _string(decoded, 'symbol'),
        name: _string(decoded, 'instrumentName'),
        tradingCurrency: currency,
      );
      final rawLots = decoded['lots'];
      if (rawLots is! List || rawLots.isEmpty || rawLots.length > 10000) {
        throw const FormatException('Invalid investment sale lots');
      }
      final lots = <InvestmentHoldingLot>[];
      for (final rawLot in rawLots) {
        if (rawLot is! Map<String, dynamic> || !_exactKeys(rawLot, _lotKeys)) {
          throw const FormatException('Invalid investment sale lot');
        }
        lots.add(
          InvestmentHoldingLot(
            id: PublicId.parse(_string(rawLot, 'id')),
            investmentAccountId: PublicId.parse(
              _string(rawLot, 'investmentAccountId'),
            ),
            instrumentId: PublicId.parse(_string(rawLot, 'instrumentId')),
            acquiredOn: BusinessDate.parse(_string(rawLot, 'acquiredOn')),
            remainingQuantity: ShareQuantity.parse(
              _string(rawLot, 'remainingQuantity'),
            ),
            remainingCost: _money(rawLot, 'remainingCostMinor', currency),
            expectedVersion: _integer(rawLot, 'expectedVersion'),
          ),
        );
      }
      final preview = InvestmentSellPreview.create(
        id: PublicId.parse(_string(decoded, 'sellId')),
        operation: OperationKey(
          workspace,
          OperationId.parse(_string(decoded, 'operationId')),
        ),
        tradedOn: BusinessDate.parse(_string(decoded, 'tradedOn')),
        broker: broker,
        account: account,
        instrument: instrument,
        funding: FundingCashAccount(
          id: fundingId,
          workspace: workspace,
          currency: currency,
          expectedVersion: _integer(decoded, 'fundingAccountVersion'),
        ),
        costMethod: switch (_string(decoded, 'costMethod')) {
          'fifo' => InvestmentCostMethod.fifo,
          'averageCost' => InvestmentCostMethod.averageCost,
          _ => throw const FormatException('Invalid cost method'),
        },
        quantity: ShareQuantity.parse(_string(decoded, 'quantity')),
        unitPrice: ShareUnitPrice.parse(
          currency,
          _string(decoded, 'unitPrice'),
        ),
        executedGross: _money(decoded, 'grossMinor', currency),
        fee: _money(decoded, 'feeMinor', currency),
        tax: _money(decoded, 'taxMinor', currency),
        lots: lots,
      );
      if (preview.cashCredit.minorUnits.toString() !=
              _string(decoded, 'cashCreditMinor') ||
          preview.allocatedCost.minorUnits.toString() !=
              _string(decoded, 'allocatedCostMinor') ||
          preview.realizedResult.minorUnits.toString() !=
              _string(decoded, 'realizedResultMinor') ||
          encode(preview) != value) {
        throw const FormatException('Noncanonical investment sale intent');
      }
      return preview;
    } on InvestmentSellException {
      throw const FormatException('Invalid investment sale intent');
    } on InvestmentException {
      throw const FormatException('Invalid investment sale intent');
    } on MoneyException {
      throw const FormatException('Invalid investment sale intent');
    } on FormatException {
      rethrow;
    }
  }
}

bool _exactKeys(Map<String, dynamic> map, Set<String> expected) =>
    map.length == expected.length && map.keys.toSet().containsAll(expected);

String _string(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String) {
    throw const FormatException('Invalid investment sale field type');
  }
  return value;
}

int _integer(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw const FormatException('Invalid investment sale field type');
  }
  return value;
}

Money _money(Map<String, dynamic> map, String key, Currency currency) {
  final value = _string(map, key);
  if (value.length > 20 || !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw const FormatException('Invalid investment sale amount');
  }
  return Money(currency, BigInt.parse(value));
}
