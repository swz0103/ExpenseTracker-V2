import 'package:foundation_values/foundation_values.dart';

enum InvestmentError {
  invalidInput,
  workspaceMismatch,
  brokerMismatch,
  fundingAccountMismatch,
  currencyMismatch,
  grossMismatch,
  duplicateIdentity,
  overflow,

  /// Taiwan-listed shares trade in whole shares only (feature audit G-16).
  fractionalShares,
}

final class InvestmentException implements Exception {
  const InvestmentException(this.code);
  final InvestmentError code;
  @override
  String toString() => 'InvestmentException(${code.name})';
}

/// User-owned identity. A broker name does not imply an external integration.
final class BrokerIdentity {
  BrokerIdentity({
    required this.id,
    required this.workspace,
    required this.name,
  }) {
    _checkName(name);
  }

  final PublicId id;
  final WorkspaceId workspace;
  final String name;
}

/// Investment identity is separate from the existing cash/bank account.
/// The linked public ID must be resolved and checked again at commit time.
final class InvestmentAccount {
  InvestmentAccount({
    required this.id,
    required this.workspace,
    required this.brokerId,
    required this.fundingCashAccountId,
    required this.name,
    required this.expectedVersion,
  }) {
    _checkName(name);
    if (expectedVersion < 1 ||
        id == brokerId ||
        id == fundingCashAccountId ||
        brokerId == fundingCashAccountId) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
  }

  final PublicId id;
  final WorkspaceId workspace;
  final PublicId brokerId;
  final PublicId fundingCashAccountId;
  final String name;
  final int expectedVersion;
}

enum InstrumentKind { stock, etf }

/// A market-qualified stock or ETF; ticker alone is never the identity.
final class InvestmentInstrument {
  InvestmentInstrument({
    required this.id,
    required this.kind,
    required this.marketCode,
    required this.symbol,
    required this.name,
    required this.tradingCurrency,
  }) {
    if (!RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(marketCode) ||
        !RegExp(r'^[A-Z0-9][A-Z0-9.\-]{0,24}$').hasMatch(symbol)) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
    _checkName(name);
  }

  final PublicId id;
  final InstrumentKind kind;
  final String marketCode;

  /// Shares on Taiwan exchanges are traded whole, odd lots included.
  bool get wholeSharesOnly => marketCode == 'TWSE' || marketCode == 'TPEX';
  final String symbol;
  final String name;
  final Currency tradingCurrency;
}

/// Snapshot of a public cash/bank account participation contract. It is not
/// proof that the account is still open or belongs to an allowed account kind.
final class FundingCashAccount {
  FundingCashAccount({
    required this.id,
    required this.workspace,
    required this.currency,
    required this.expectedVersion,
  }) {
    if (expectedVersion < 1) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
  }

  final PublicId id;
  final WorkspaceId workspace;
  final Currency currency;
  final int expectedVersion;
}

/// Exact positive share quantity, at most 12 decimal places.
final class ShareQuantity {
  ShareQuantity._(this._decimal);
  factory ShareQuantity.parse(String input) =>
      ShareQuantity._(_PositiveDecimal.parse(input));

  final _PositiveDecimal _decimal;
  BigInt get coefficient => _decimal.coefficient;
  int get scale => _decimal.scale;

  /// No fraction of a share.
  bool get isWhole => coefficient % BigInt.from(10).pow(scale) == BigInt.zero;
  @override
  String toString() => _decimal.input;
  @override
  bool operator ==(Object other) =>
      other is ShareQuantity &&
      coefficient == other.coefficient &&
      scale == other.scale;
  @override
  int get hashCode => Object.hash(coefficient, scale);
}

/// Exact trade-currency amount per share, at most 12 decimal places.
final class ShareUnitPrice {
  ShareUnitPrice._(this.currency, this._decimal);
  factory ShareUnitPrice.parse(Currency currency, String input) =>
      ShareUnitPrice._(currency, _PositiveDecimal.parse(input));

  final Currency currency;
  final _PositiveDecimal _decimal;
  BigInt get coefficient => _decimal.coefficient;
  int get scale => _decimal.scale;
  @override
  String toString() => _decimal.input;
  @override
  bool operator ==(Object other) =>
      other is ShareUnitPrice &&
      currency == other.currency &&
      coefficient == other.coefficient &&
      scale == other.scale;
  @override
  int get hashCode => Object.hash(currency, coefficient, scale);
}

/// Proposed authoritative acquisition record. It is not a committed lot.
final class AcquisitionLot {
  const AcquisitionLot._({
    required this.id,
    required this.buyId,
    required this.investmentAccountId,
    required this.instrumentId,
    required this.acquiredOn,
    required this.quantity,
    required this.unitPrice,
    required this.gross,
    required this.fee,
    required this.tax,
    required this.acquisitionCashCost,
  });

  final PublicId id;
  final PublicId buyId;
  final PublicId investmentAccountId;
  final PublicId instrumentId;
  final BusinessDate acquiredOn;
  final ShareQuantity quantity;
  final ShareUnitPrice unitPrice;
  final Money gross;
  final Money fee;
  final Money tax;

  /// Cash paid to acquire the lot; tax-jurisdiction cost basis is separate.
  final Money acquisitionCashCost;
}

/// Pure preview: exact quote calculation, explicit settlement and one proposed
/// lot. Application must commit the lot and a non-consumption cash debit in one
/// SQLite transaction under [operation], including an idempotency receipt.
final class InvestmentBuyPreview {
  InvestmentBuyPreview._({
    required this.id,
    required this.operation,
    required this.tradedOn,
    required this.broker,
    required this.account,
    required this.instrument,
    required this.funding,
    required this.quantity,
    required this.unitPrice,
    required this.gross,
    required this.fee,
    required this.tax,
    required this.cashDebit,
    required this.lot,
    required this.exactGrossNumerator,
    required this.exactGrossDenominator,
  });

  factory InvestmentBuyPreview.create({
    required PublicId id,
    required PublicId lotId,
    required OperationKey operation,
    required BusinessDate tradedOn,
    required BrokerIdentity broker,
    required InvestmentAccount account,
    required InvestmentInstrument instrument,
    required FundingCashAccount funding,
    required ShareQuantity quantity,
    required ShareUnitPrice unitPrice,
    required Money executedGross,
    required Money fee,
    required Money tax,
  }) {
    if (id == lotId) {
      throw const InvestmentException(InvestmentError.duplicateIdentity);
    }
    if (operation.workspace != broker.workspace ||
        operation.workspace != account.workspace ||
        operation.workspace != funding.workspace) {
      throw const InvestmentException(InvestmentError.workspaceMismatch);
    }
    if (account.brokerId != broker.id) {
      throw const InvestmentException(InvestmentError.brokerMismatch);
    }
    if (account.fundingCashAccountId != funding.id) {
      throw const InvestmentException(InvestmentError.fundingAccountMismatch);
    }
    final currency = instrument.tradingCurrency;
    if (funding.currency != currency ||
        unitPrice.currency != currency ||
        executedGross.currency != currency ||
        fee.currency != currency ||
        tax.currency != currency) {
      throw const InvestmentException(InvestmentError.currencyMismatch);
    }
    if (executedGross.minorUnits <= BigInt.zero ||
        fee.minorUnits < BigInt.zero ||
        tax.minorUnits < BigInt.zero) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
    final numerator = quantity.coefficient * unitPrice.coefficient;
    final denominator = BigInt.from(10).pow(quantity.scale + unitPrice.scale);
    late final Money calculatedGross;
    try {
      // One explicit final settlement boundary; no double or intermediate FX.
      calculatedGross = Money.quantizeRatio(currency, numerator, denominator);
    } on MoneyException catch (error) {
      if (error.code == MoneyError.overflow) {
        throw const InvestmentException(InvestmentError.overflow);
      }
      rethrow;
    }
    // Brokers round the gross their own way; one unit either side is
    // accepted (feature audit G-16).
    if ((calculatedGross.minorUnits - executedGross.minorUnits).abs() >
        BigInt.one) {
      throw const InvestmentException(InvestmentError.grossMismatch);
    }
    if (instrument.wholeSharesOnly && !quantity.isWhole) {
      throw const InvestmentException(InvestmentError.fractionalShares);
    }
    final debitUnits =
        executedGross.minorUnits + fee.minorUnits + tax.minorUnits;
    if (debitUnits > Money.maxMinorUnits) {
      throw const InvestmentException(InvestmentError.overflow);
    }
    final debit = Money(currency, debitUnits);
    final lot = AcquisitionLot._(
      id: lotId,
      buyId: id,
      investmentAccountId: account.id,
      instrumentId: instrument.id,
      acquiredOn: tradedOn,
      quantity: quantity,
      unitPrice: unitPrice,
      gross: executedGross,
      fee: fee,
      tax: tax,
      acquisitionCashCost: debit,
    );
    return InvestmentBuyPreview._(
      id: id,
      operation: operation,
      tradedOn: tradedOn,
      broker: broker,
      account: account,
      instrument: instrument,
      funding: funding,
      quantity: quantity,
      unitPrice: unitPrice,
      gross: executedGross,
      fee: fee,
      tax: tax,
      cashDebit: debit,
      lot: lot,
      exactGrossNumerator: numerator,
      exactGrossDenominator: denominator,
    );
  }

  final PublicId id;
  final OperationKey operation;
  final BusinessDate tradedOn;
  final BrokerIdentity broker;
  final InvestmentAccount account;
  final InvestmentInstrument instrument;
  final FundingCashAccount funding;
  final ShareQuantity quantity;
  final ShareUnitPrice unitPrice;
  final Money gross;
  final Money fee;
  final Money tax;
  final Money cashDebit;
  final AcquisitionLot lot;
  final BigInt exactGrossNumerator;
  final BigInt exactGrossDenominator;
  static const settlementRoundingPolicy = 'half-away-from-zero-v1';
}

final class _PositiveDecimal {
  const _PositiveDecimal(this.coefficient, this.scale, this.input);
  static _PositiveDecimal parse(String input) {
    if (input.length > 40 ||
        !RegExp(r'^(0|[1-9][0-9]{0,23})(\.[0-9]{1,12})?$').hasMatch(input)) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
    final parts = input.split('.');
    var coefficient = BigInt.parse(parts.join());
    if (coefficient <= BigInt.zero) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
    var scale = parts.length == 1 ? 0 : parts[1].length;
    while (scale > 0 && coefficient.remainder(BigInt.from(10)) == BigInt.zero) {
      coefficient ~/= BigInt.from(10);
      scale--;
    }
    return _PositiveDecimal(coefficient, scale, input);
  }

  final BigInt coefficient;
  final int scale;
  final String input;
}

void _checkName(String value) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.runes.length > 120 ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
    throw const InvestmentException(InvestmentError.invalidInput);
  }
}
