import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';

import 'commands.dart';

abstract base class _InvestmentCommand<R> implements Command<R> {
  _InvestmentCommand(this.operation);

  @override
  final OperationKey operation;

  Map<String, Object?> get fields;

  @override
  String get input => jsonEncode(fields);
}

/// Commands that register something return its version (always 1).
abstract base class _Registration extends _InvestmentCommand<int> {
  _Registration(super.operation);

  @override
  String encodeResult(int result) => '$result';

  @override
  int decodeResult(String encoded) => int.parse(encoded);
}

/// Trades return the id of the cash posting they recorded.
abstract base class _Trade extends _InvestmentCommand<PublicId> {
  _Trade(super.operation);

  @override
  String encodeResult(PublicId result) => result.value;

  @override
  PublicId decodeResult(String encoded) => PublicId.parse(encoded);
}

final class RegisterBroker extends _Registration {
  RegisterBroker({
    required OperationKey operation,
    required this.brokerId,
    required this.name,
  }) : super(operation);

  final PublicId brokerId;
  final String name;

  @override
  Map<String, Object?> get fields => {
    'command': 'register-broker-v1',
    'brokerId': brokerId.value,
    'name': name,
  };
}

/// A brokerage account settled through one cash or bank account.
final class OpenInvestmentAccount extends _Registration {
  OpenInvestmentAccount({
    required OperationKey operation,
    required this.accountId,
    required this.brokerId,
    required this.fundingAccountId,
    required this.name,
  }) : super(operation);

  final PublicId accountId;
  final PublicId brokerId;
  final PublicId fundingAccountId;
  final String name;

  @override
  Map<String, Object?> get fields => {
    'command': 'open-investment-account-v1',
    'accountId': accountId.value,
    'brokerId': brokerId.value,
    'fundingAccountId': fundingAccountId.value,
    'name': name,
  };
}

final class RegisterInstrument extends _Registration {
  RegisterInstrument({
    required OperationKey operation,
    required this.instrumentId,
    required this.kind,
    required this.marketCode,
    required this.symbol,
    required this.name,
    required this.currency,
  }) : super(operation);

  final PublicId instrumentId;
  final InstrumentKind kind;
  final String marketCode;
  final String symbol;
  final String name;
  final Currency currency;

  @override
  Map<String, Object?> get fields => {
    'command': 'register-instrument-v1',
    'instrumentId': instrumentId.value,
    'kind': kind.name,
    'marketCode': marketCode,
    'symbol': symbol,
    'name': name,
    'currency': currency.code,
    'scale': currency.scale,
  };
}

/// Fields every trade shares: who, what, and the funding account version
/// the person saw.
final class TradeTarget {
  const TradeTarget({
    required this.accountId,
    required this.instrumentId,
    required this.funding,
  });

  final PublicId accountId;
  final PublicId instrumentId;
  final AccountRef funding;

  Map<String, Object?> toJson() => {
    'accountId': accountId.value,
    'instrumentId': instrumentId.value,
    'funding': funding.toJson(),
  };
}

final class BuyInvestment extends _Trade {
  BuyInvestment({
    required OperationKey operation,
    required this.buyId,
    required this.lotId,
    required this.postingId,
    required this.target,
    required this.tradedOn,
    required this.quantity,
    required this.unitPrice,
    required this.gross,
    required this.fee,
    required this.tax,
  }) : super(operation);

  final PublicId buyId;
  final PublicId lotId;
  final PublicId postingId;
  final TradeTarget target;
  final BusinessDate tradedOn;

  /// Exact decimal text, for example `10` or `0.5`.
  final String quantity;
  final String unitPrice;
  final Money gross;
  final Money fee;
  final Money tax;

  @override
  Map<String, Object?> get fields => {
    'command': 'buy-investment-v1',
    'buyId': buyId.value,
    'lotId': lotId.value,
    'postingId': postingId.value,
    ...target.toJson(),
    'tradedOn': tradedOn.toString(),
    'quantity': quantity,
    'unitPrice': unitPrice,
    'gross': gross.toJson(),
    'fee': fee.toJson(),
    'tax': tax.toJson(),
  };
}

final class SellInvestment extends _Trade {
  SellInvestment({
    required OperationKey operation,
    required this.sellId,
    required this.postingId,
    required this.target,
    required this.tradedOn,
    required this.costMethod,
    required this.quantity,
    required this.unitPrice,
    required this.gross,
    required this.fee,
    required this.tax,
  }) : super(operation);

  final PublicId sellId;
  final PublicId postingId;
  final TradeTarget target;
  final BusinessDate tradedOn;
  final InvestmentCostMethod costMethod;
  final String quantity;
  final String unitPrice;
  final Money gross;
  final Money fee;
  final Money tax;

  @override
  Map<String, Object?> get fields => {
    'command': 'sell-investment-v1',
    'sellId': sellId.value,
    'postingId': postingId.value,
    ...target.toJson(),
    'tradedOn': tradedOn.toString(),
    'costMethod': costMethod.name,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'gross': gross.toJson(),
    'fee': fee.toJson(),
    'tax': tax.toJson(),
  };
}

/// A broker-reported cash dividend in the instrument's currency.
final class RecordDividend extends _Trade {
  RecordDividend({
    required OperationKey operation,
    required this.dividendId,
    required this.postingId,
    required this.target,
    required this.paidOn,
    required this.gross,
    required this.withholdingTax,
    required this.fee,
    required this.net,
  }) : super(operation);

  final PublicId dividendId;
  final PublicId postingId;
  final TradeTarget target;
  final BusinessDate paidOn;
  final Money gross;
  final Money withholdingTax;
  final Money fee;
  final Money net;

  @override
  Map<String, Object?> get fields => {
    'command': 'record-dividend-v1',
    'dividendId': dividendId.value,
    'postingId': postingId.value,
    ...target.toJson(),
    'paidOn': paidOn.toString(),
    'gross': gross.toJson(),
    'withholdingTax': withholdingTax.toJson(),
    'fee': fee.toJson(),
    'net': net.toJson(),
  };
}

/// A forward split, for example 4-for-1. Quantities change, cost does not,
/// and no cash moves. Returns the number of lots changed.
final class SplitInvestment extends _Registration {
  SplitInvestment({
    required OperationKey operation,
    required this.splitId,
    required this.accountId,
    required this.instrumentId,
    required this.effectiveOn,
    required this.newShares,
    required this.oldShares,
  }) : super(operation);

  final PublicId splitId;
  final PublicId accountId;
  final PublicId instrumentId;
  final BusinessDate effectiveOn;
  final int newShares;
  final int oldShares;

  @override
  Map<String, Object?> get fields => {
    'command': 'split-investment-v1',
    'splitId': splitId.value,
    'accountId': accountId.value,
    'instrumentId': instrumentId.value,
    'effectiveOn': effectiveOn.toString(),
    'newShares': newShares,
    'oldShares': oldShares,
  };
}

/// Removes a trade entered by mistake. Its cash posting, if any, is
/// reversed on its own date and the holding is replayed without it. A
/// dividend can always be voided; a buy, sell or split only while no later
/// buy, sell or split of the same holding depends on it. Returns the
/// trade id.
final class VoidInvestmentTrade extends _Trade {
  VoidInvestmentTrade({
    required OperationKey operation,
    required this.accountId,
    required this.instrumentId,
    required this.tradeId,
    required this.reversalId,
  }) : super(operation);

  final PublicId accountId;
  final PublicId instrumentId;
  final PublicId tradeId;

  /// The reversal posting, when the trade moved cash.
  final PublicId reversalId;

  @override
  Map<String, Object?> get fields => {
    'command': 'void-investment-trade-v1',
    'accountId': accountId.value,
    'instrumentId': instrumentId.value,
    'tradeId': tradeId.value,
    'reversalId': reversalId.value,
  };
}
