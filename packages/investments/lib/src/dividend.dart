import 'package:foundation_values/foundation_values.dart';

import 'buy.dart';

enum InvestmentDividendError {
  invalidInput,
  workspaceMismatch,
  brokerMismatch,
  fundingAccountMismatch,
  currencyMismatch,
  netMismatch,
}

final class InvestmentDividendException implements Exception {
  const InvestmentDividendException(this.code);
  final InvestmentDividendError code;

  @override
  String toString() => 'InvestmentDividendException(${code.name})';
}

/// A broker-reported cash dividend, not an inferred entitlement or market
/// quote. The cash credit and immutable dividend fact must commit together.
/// This first route supports settlement in the instrument's own currency only.
final class InvestmentDividendPreview {
  InvestmentDividendPreview._({
    required this.id,
    required this.operation,
    required this.paidOn,
    required this.broker,
    required this.account,
    required this.instrument,
    required this.funding,
    required this.gross,
    required this.withholdingTax,
    required this.fee,
    required this.netCashCredit,
  });

  factory InvestmentDividendPreview.create({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate paidOn,
    required BrokerIdentity broker,
    required InvestmentAccount account,
    required InvestmentInstrument instrument,
    required FundingCashAccount funding,
    required Money gross,
    required Money withholdingTax,
    required Money fee,
    required Money reportedNet,
  }) {
    if (operation.workspace != broker.workspace ||
        operation.workspace != account.workspace ||
        operation.workspace != funding.workspace) {
      throw const InvestmentDividendException(
        InvestmentDividendError.workspaceMismatch,
      );
    }
    if (account.brokerId != broker.id) {
      throw const InvestmentDividendException(
        InvestmentDividendError.brokerMismatch,
      );
    }
    if (account.fundingCashAccountId != funding.id) {
      throw const InvestmentDividendException(
        InvestmentDividendError.fundingAccountMismatch,
      );
    }
    final currency = instrument.tradingCurrency;
    if (funding.currency != currency ||
        gross.currency != currency ||
        withholdingTax.currency != currency ||
        fee.currency != currency ||
        reportedNet.currency != currency) {
      throw const InvestmentDividendException(
        InvestmentDividendError.currencyMismatch,
      );
    }
    if (gross.minorUnits <= BigInt.zero ||
        withholdingTax.minorUnits < BigInt.zero ||
        fee.minorUnits < BigInt.zero ||
        reportedNet.minorUnits < BigInt.zero ||
        id == broker.id ||
        id == account.id ||
        id == instrument.id ||
        id == funding.id) {
      throw const InvestmentDividendException(
        InvestmentDividendError.invalidInput,
      );
    }
    final netUnits =
        gross.minorUnits - withholdingTax.minorUnits - fee.minorUnits;
    // Everything withheld leaves nothing to pay out (health check G1-06).
    if (netUnits != reportedNet.minorUnits) {
      throw const InvestmentDividendException(
        InvestmentDividendError.netMismatch,
      );
    }
    return InvestmentDividendPreview._(
      id: id,
      operation: operation,
      paidOn: paidOn,
      broker: broker,
      account: account,
      instrument: instrument,
      funding: funding,
      gross: gross,
      withholdingTax: withholdingTax,
      fee: fee,
      netCashCredit: reportedNet,
    );
  }

  final PublicId id;
  final OperationKey operation;
  final BusinessDate paidOn;
  final BrokerIdentity broker;
  final InvestmentAccount account;
  final InvestmentInstrument instrument;
  final FundingCashAccount funding;
  final Money gross;
  final Money withholdingTax;
  final Money fee;
  final Money netCashCredit;
}
