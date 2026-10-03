import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';

import 'buy.dart';
import 'dividend.dart';

/// Canonical private retry intent; authority is checked again at commit.
final class InvestmentDividendPreviewCodec {
  const InvestmentDividendPreviewCodec();

  static const formatVersion = 1;
  static const maxBytes = 4096;
  static const _keys = {
    'format',
    'dividendId',
    'workspace',
    'operationId',
    'paidOn',
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
    'grossMinor',
    'withholdingTaxMinor',
    'feeMinor',
    'netCashCreditMinor',
  };

  String encode(InvestmentDividendPreview preview) {
    final value = jsonEncode({
      'format': formatVersion,
      'dividendId': preview.id.value,
      'workspace': preview.operation.workspace.id.value,
      'operationId': preview.operation.operation.id.value,
      'paidOn': preview.paidOn.toString(),
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
      'grossMinor': preview.gross.minorUnits.toString(),
      'withholdingTaxMinor': preview.withholdingTax.minorUnits.toString(),
      'feeMinor': preview.fee.minorUnits.toString(),
      'netCashCreditMinor': preview.netCashCredit.minorUnits.toString(),
    });
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Investment dividend intent too large');
    }
    return value;
  }

  InvestmentDividendPreview decode(String value) {
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Investment dividend intent too large');
    }
    final Object? raw;
    try {
      raw = jsonDecode(value);
    } on FormatException {
      throw const FormatException('Invalid investment dividend JSON');
    }
    if (raw is! Map<String, dynamic> ||
        raw.length != _keys.length ||
        !raw.keys.toSet().containsAll(_keys) ||
        raw['format'] != formatVersion) {
      throw const FormatException('Invalid investment dividend fields');
    }
    try {
      final workspace = WorkspaceId.parse(_string(raw, 'workspace'));
      final currency = Currency(
        _string(raw, 'currency'),
        _integer(raw, 'currencyScale'),
      );
      final broker = BrokerIdentity(
        id: PublicId.parse(_string(raw, 'brokerId')),
        workspace: workspace,
        name: _string(raw, 'brokerName'),
      );
      final fundingId = PublicId.parse(_string(raw, 'fundingAccountId'));
      final account = InvestmentAccount(
        id: PublicId.parse(_string(raw, 'investmentAccountId')),
        workspace: workspace,
        brokerId: broker.id,
        fundingCashAccountId: fundingId,
        name: _string(raw, 'investmentAccountName'),
        expectedVersion: _integer(raw, 'investmentAccountVersion'),
      );
      final instrument = InvestmentInstrument(
        id: PublicId.parse(_string(raw, 'instrumentId')),
        kind: switch (_string(raw, 'instrumentKind')) {
          'stock' => InstrumentKind.stock,
          'etf' => InstrumentKind.etf,
          _ => throw const FormatException('Invalid instrument kind'),
        },
        marketCode: _string(raw, 'marketCode'),
        symbol: _string(raw, 'symbol'),
        name: _string(raw, 'instrumentName'),
        tradingCurrency: currency,
      );
      final preview = InvestmentDividendPreview.create(
        id: PublicId.parse(_string(raw, 'dividendId')),
        operation: OperationKey(
          workspace,
          OperationId.parse(_string(raw, 'operationId')),
        ),
        paidOn: BusinessDate.parse(_string(raw, 'paidOn')),
        broker: broker,
        account: account,
        instrument: instrument,
        funding: FundingCashAccount(
          id: fundingId,
          workspace: workspace,
          currency: currency,
          expectedVersion: _integer(raw, 'fundingAccountVersion'),
        ),
        gross: _money(raw, 'grossMinor', currency),
        withholdingTax: _money(raw, 'withholdingTaxMinor', currency),
        fee: _money(raw, 'feeMinor', currency),
        reportedNet: _money(raw, 'netCashCreditMinor', currency),
      );
      if (encode(preview) != value) {
        throw const FormatException('Noncanonical investment dividend intent');
      }
      return preview;
    } on InvestmentDividendException {
      throw const FormatException('Invalid investment dividend intent');
    } on InvestmentException {
      throw const FormatException('Invalid investment dividend intent');
    } on MoneyException {
      throw const FormatException('Invalid investment dividend intent');
    } on FormatException {
      rethrow;
    }
  }
}

String _string(Map<String, dynamic> raw, String key) {
  final value = raw[key];
  if (value is! String) throw const FormatException('Invalid dividend field');
  return value;
}

int _integer(Map<String, dynamic> raw, String key) {
  final value = raw[key];
  if (value is! int) throw const FormatException('Invalid dividend field');
  return value;
}

Money _money(Map<String, dynamic> raw, String key, Currency currency) {
  final value = _string(raw, key);
  if (value.length > 20 || !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw const FormatException('Invalid dividend amount');
  }
  return Money(currency, parseMinorUnits(value));
}
