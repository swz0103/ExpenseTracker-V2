import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';

import 'buy.dart';

/// Canonical retry intent. This is neither an authenticated backup nor proof
/// that the referenced cash account is still eligible at commit time.
final class InvestmentBuyPreviewCodec {
  const InvestmentBuyPreviewCodec();

  static const formatVersion = 1;
  static const maxBytes = 4096;
  static const _keys = {
    'format',
    'buyId',
    'lotId',
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
    'quantity',
    'unitPrice',
    'grossMinor',
    'feeMinor',
    'taxMinor',
    'cashDebitMinor',
    'roundingPolicy',
  };

  String encode(InvestmentBuyPreview preview) {
    final value = jsonEncode({
      'format': formatVersion,
      'buyId': preview.id.value,
      'lotId': preview.lot.id.value,
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
      'quantity': preview.quantity.toString(),
      'unitPrice': preview.unitPrice.toString(),
      'grossMinor': preview.gross.minorUnits.toString(),
      'feeMinor': preview.fee.minorUnits.toString(),
      'taxMinor': preview.tax.minorUnits.toString(),
      'cashDebitMinor': preview.cashDebit.minorUnits.toString(),
      'roundingPolicy': InvestmentBuyPreview.settlementRoundingPolicy,
    });
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Investment intent exceeds size limit');
    }
    return value;
  }

  InvestmentBuyPreview decode(String value) {
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Investment intent exceeds size limit');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw const FormatException('Invalid investment intent JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.toSet().length != _keys.length ||
        !decoded.keys.toSet().containsAll(_keys) ||
        decoded['format'] != formatVersion ||
        decoded['roundingPolicy'] !=
            InvestmentBuyPreview.settlementRoundingPolicy) {
      throw const FormatException('Invalid investment intent fields');
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
      final preview = InvestmentBuyPreview.create(
        id: PublicId.parse(_string(decoded, 'buyId')),
        lotId: PublicId.parse(_string(decoded, 'lotId')),
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
        quantity: ShareQuantity.parse(_string(decoded, 'quantity')),
        unitPrice: ShareUnitPrice.parse(
          currency,
          _string(decoded, 'unitPrice'),
        ),
        executedGross: _money(decoded, 'grossMinor', currency),
        fee: _money(decoded, 'feeMinor', currency),
        tax: _money(decoded, 'taxMinor', currency),
      );
      // Recalculation rejects altered gross/debit and re-encoding rejects
      // noncanonical IDs, money text, field order, whitespace and escapes.
      if (preview.cashDebit.minorUnits.toString() !=
              _string(decoded, 'cashDebitMinor') ||
          encode(preview) != value) {
        throw const FormatException('Noncanonical investment intent');
      }
      return preview;
    } on InvestmentException {
      throw const FormatException('Invalid investment intent');
    } on MoneyException {
      throw const FormatException('Invalid investment intent');
    } on FormatException {
      rethrow;
    }
  }
}

String _string(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String) {
    throw const FormatException('Invalid investment intent field type');
  }
  return value;
}

int _integer(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw const FormatException('Invalid investment intent field type');
  }
  return value;
}

Money _money(Map<String, dynamic> map, String key, Currency currency) {
  final value = _string(map, key);
  if (value.length > 20 || !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw const FormatException('Invalid investment amount');
  }
  return Money(currency, parseMinorUnits(value));
}
