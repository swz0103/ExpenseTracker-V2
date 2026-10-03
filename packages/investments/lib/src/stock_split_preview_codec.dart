import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';

import 'buy.dart';
import 'sell.dart';
import 'stock_split.dart';

/// Canonical private retry intent. Authoritative lots are re-read at commit.
final class StockSplitPreviewCodec {
  const StockSplitPreviewCodec();

  static const formatVersion = 1;
  static const maxBytes = 256 * 1024;
  static const _keys = {
    'format',
    'splitId',
    'workspace',
    'operationId',
    'effectiveOn',
    'brokerId',
    'brokerName',
    'investmentAccountId',
    'investmentAccountName',
    'investmentAccountVersion',
    'fundingAccountId',
    'instrumentId',
    'instrumentKind',
    'marketCode',
    'symbol',
    'instrumentName',
    'currency',
    'currencyScale',
    'newShares',
    'oldShares',
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

  String encode(StockSplitPreview preview) {
    final value = jsonEncode({
      'format': formatVersion,
      'splitId': preview.id.value,
      'workspace': preview.operation.workspace.id.value,
      'operationId': preview.operation.operation.id.value,
      'effectiveOn': preview.effectiveOn.toString(),
      'brokerId': preview.broker.id.value,
      'brokerName': preview.broker.name,
      'investmentAccountId': preview.account.id.value,
      'investmentAccountName': preview.account.name,
      'investmentAccountVersion': preview.account.expectedVersion,
      'fundingAccountId': preview.account.fundingCashAccountId.value,
      'instrumentId': preview.instrument.id.value,
      'instrumentKind': preview.instrument.kind.name,
      'marketCode': preview.instrument.marketCode,
      'symbol': preview.instrument.symbol,
      'instrumentName': preview.instrument.name,
      'currency': preview.instrument.tradingCurrency.code,
      'currencyScale': preview.instrument.tradingCurrency.scale,
      'newShares': preview.newShares,
      'oldShares': preview.oldShares,
      'lots': [
        for (final change in preview.lots)
          {
            'id': change.before.id.value,
            'investmentAccountId': change.before.investmentAccountId.value,
            'instrumentId': change.before.instrumentId.value,
            'acquiredOn': change.before.acquiredOn.toString(),
            'remainingQuantity': change.before.remainingQuantity.toString(),
            'remainingCostMinor': change.before.remainingCost.minorUnits
                .toString(),
            'expectedVersion': change.before.expectedVersion,
          },
      ],
    });
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Investment split intent too large');
    }
    return value;
  }

  StockSplitPreview decode(String value) {
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Investment split intent too large');
    }
    final Object? raw;
    try {
      raw = jsonDecode(value);
    } on FormatException {
      throw const FormatException('Invalid investment split JSON');
    }
    if (raw is! Map<String, dynamic> ||
        raw.length != _keys.length ||
        !raw.keys.toSet().containsAll(_keys) ||
        raw['format'] != formatVersion) {
      throw const FormatException('Invalid investment split fields');
    }
    try {
      final data = raw;
      String string(String key) {
        final field = data[key];
        if (field is! String)
          throw const FormatException('Invalid split field');
        return field;
      }

      int integer(String key) {
        final field = data[key];
        if (field is! int) throw const FormatException('Invalid split field');
        return field;
      }

      final workspace = WorkspaceId.parse(string('workspace'));
      final currency = Currency(string('currency'), integer('currencyScale'));
      final broker = BrokerIdentity(
        id: PublicId.parse(string('brokerId')),
        workspace: workspace,
        name: string('brokerName'),
      );
      final account = InvestmentAccount(
        id: PublicId.parse(string('investmentAccountId')),
        workspace: workspace,
        brokerId: broker.id,
        fundingCashAccountId: PublicId.parse(string('fundingAccountId')),
        name: string('investmentAccountName'),
        expectedVersion: integer('investmentAccountVersion'),
      );
      final instrument = InvestmentInstrument(
        id: PublicId.parse(string('instrumentId')),
        kind: switch (string('instrumentKind')) {
          'stock' => InstrumentKind.stock,
          'etf' => InstrumentKind.etf,
          _ => throw const FormatException('Invalid split instrument'),
        },
        marketCode: string('marketCode'),
        symbol: string('symbol'),
        name: string('instrumentName'),
        tradingCurrency: currency,
      );
      final rawLots = data['lots'];
      if (rawLots is! List || rawLots.isEmpty || rawLots.length > 5000) {
        throw const FormatException('Invalid split lots');
      }
      final lots = <InvestmentHoldingLot>[];
      for (final element in rawLots) {
        if (element is! Map<String, dynamic> ||
            element.length != _lotKeys.length ||
            !element.keys.toSet().containsAll(_lotKeys)) {
          throw const FormatException('Invalid split lot fields');
        }
        final costText = element['remainingCostMinor'];
        if (costText is! String ||
            costText.length > 20 ||
            !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(costText)) {
          throw const FormatException('Invalid split cost');
        }
        lots.add(
          InvestmentHoldingLot(
            id: PublicId.parse(element['id'] as String),
            investmentAccountId: PublicId.parse(
              element['investmentAccountId'] as String,
            ),
            instrumentId: PublicId.parse(element['instrumentId'] as String),
            acquiredOn: BusinessDate.parse(element['acquiredOn'] as String),
            remainingQuantity: ShareQuantity.parse(
              element['remainingQuantity'] as String,
            ),
            remainingCost: Money(currency, parseMinorUnits(costText)),
            expectedVersion: element['expectedVersion'] as int,
          ),
        );
      }
      final preview = StockSplitPreview.create(
        id: PublicId.parse(string('splitId')),
        operation: OperationKey(
          workspace,
          OperationId.parse(string('operationId')),
        ),
        effectiveOn: BusinessDate.parse(string('effectiveOn')),
        broker: broker,
        account: account,
        instrument: instrument,
        newShares: integer('newShares'),
        oldShares: integer('oldShares'),
        lots: lots,
      );
      if (encode(preview) != value) {
        throw const FormatException('Noncanonical split intent');
      }
      return preview;
    } catch (_) {
      throw const FormatException('Invalid investment split intent');
    }
  }
}
