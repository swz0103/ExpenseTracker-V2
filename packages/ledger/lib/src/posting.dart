import 'package:foundation_values/foundation_values.dart';

part 'refund.dart';

enum PostingKind {
  opening,
  income,
  expense,
  transfer,
  refund,
  reversal,
  investmentBuy,
  investmentSell,
  investmentDividend,
}

enum LegRole { principal, fee }

enum LedgerError {
  invalidAmount,
  workspaceMismatch,
  currencyMismatch,
  sameAccount,
  allocationMismatch,
  duplicateIdentity,
  refundReference,
  refundLimit,
  reversalReference,
  reversalDependency,
  correctionReference,
  tombstoneReference,
  tombstoneDependency,
  investmentBuyMismatch,
  investmentSellMismatch,
  investmentDividendMismatch,
}

final class LedgerException implements Exception {
  const LedgerException(this.code);
  final LedgerError code;
  @override
  String toString() => 'LedgerException(${code.name})';
}

/// Public participation contract; Application resolves current Account rules.
final class PostingAccount {
  PostingAccount({
    required this.id,
    required this.workspace,
    required this.currency,
    required this.expectedVersion,
  }) {
    if (expectedVersion < 1)
      throw ArgumentError('Expected a positive account version.');
  }
  final PublicId id;
  final WorkspaceId workspace;
  final Currency currency;
  final int expectedVersion;
}

final class LedgerLeg {
  const LedgerLeg._(this.account, this.amount, this.role);
  final PostingAccount account;
  final Money amount;
  final LegRole role;
}

/// Analysis attribution, never an additional cash movement.
final class Allocation {
  Allocation(this.categoryId, this.amount, {this.expectedCategoryVersion}) {
    if (amount.minorUnits <= BigInt.zero)
      throw const LedgerException(LedgerError.invalidAmount);
    if (expectedCategoryVersion != null && expectedCategoryVersion! < 1) {
      throw ArgumentError('Expected a positive category version.');
    }
  }
  final PublicId categoryId;
  final Money amount;

  /// Required by versioned persistence; null keeps old domain proposals readable.
  final int? expectedCategoryVersion;
}

/// Ledger-side cash breakdown for one investment acquisition. The investment
/// module owns the quote, instrument and lot; this records only the validated
/// cash effect and a link to the buy committed with it.
final class InvestmentBuyCashDetails {
  const InvestmentBuyCashDetails._({
    required this.buyId,
    required this.gross,
    required this.fee,
    required this.tax,
    required this.cashDebit,
  });

  final PublicId buyId;
  final Money gross;
  final Money fee;
  final Money tax;
  final Money cashDebit;
}

/// Cash settlement for a sale. The investment module owns disposed lots and
/// realized profit; proceeds must never enter ordinary income totals.
final class InvestmentSellCashDetails {
  const InvestmentSellCashDetails._({
    required this.sellId,
    required this.gross,
    required this.fee,
    required this.tax,
    required this.cashCredit,
  });

  final PublicId sellId;
  final Money gross;
  final Money fee;
  final Money tax;
  final Money cashCredit;
}

/// The broker-reported dividend is investment income, separate from ordinary
/// income reports. Its investment fact must be saved with this cash credit.
final class InvestmentDividendCashDetails {
  const InvestmentDividendCashDetails._({
    required this.dividendId,
    required this.gross,
    required this.withholdingTax,
    required this.fee,
    required this.cashCredit,
  });

  final PublicId dividendId;
  final Money gross;
  final Money withholdingTax;
  final Money fee;
  final Money cashCredit;
}

/// Validated immutable posting proposal. Has no financial effect until committed.
final class Posting {
  Posting._({
    required this.id,
    required this.operation,
    required this.date,
    required this.kind,
    required List<LedgerLeg> legs,
    required this.reportIncome,
    required this.reportExpense,
    this.conversion,
    this.refundOf,
    this.reversedPosting,
    this.reversalReason,
    this.investmentBuy,
    this.investmentSell,
    this.investmentDividend,
    List<Allocation> allocations = const [],
  }) : legs = List.unmodifiable(legs),
       allocations = List.unmodifiable(allocations);

  factory Posting.opening({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate date,
    required PostingAccount account,
    required Money amount,
  }) {
    _participation(operation, account, amount);
    final zero = Money(account.currency, BigInt.zero);
    return Posting._(
      id: id,
      operation: operation,
      date: date,
      kind: PostingKind.opening,
      legs: [LedgerLeg._(account, amount, LegRole.principal)],
      reportIncome: zero,
      reportExpense: zero,
    );
  }

  factory Posting.income({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate date,
    required PostingAccount account,
    required Money amount,
    List<Allocation> allocations = const [],
  }) {
    _participation(operation, account, amount);
    _positive(amount);
    _allocations(amount, allocations);
    return Posting._(
      id: id,
      operation: operation,
      date: date,
      kind: PostingKind.income,
      legs: [LedgerLeg._(account, amount, LegRole.principal)],
      reportIncome: amount,
      reportExpense: Money(account.currency, BigInt.zero),
      allocations: allocations,
    );
  }

  factory Posting.expense({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate date,
    required PostingAccount account,
    required Money amount,
    List<Allocation> allocations = const [],
  }) {
    _participation(operation, account, amount);
    _positive(amount);
    _allocations(amount, allocations);
    return Posting._(
      id: id,
      operation: operation,
      date: date,
      kind: PostingKind.expense,
      legs: [LedgerLeg._(account, -amount, LegRole.principal)],
      reportIncome: Money(account.currency, BigInt.zero),
      reportExpense: amount,
      allocations: allocations,
    );
  }

  /// Debits cash for an investment acquisition without recording consumption.
  /// Application must compare these values and identities with its validated
  /// InvestmentBuyPreview and commit both records in the same transaction.
  factory Posting.investmentBuy({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate date,
    required PostingAccount account,
    required PublicId investmentBuyId,
    required Money gross,
    required Money fee,
    required Money tax,
    required Money cashDebit,
  }) {
    _participation(operation, account, gross);
    _participation(operation, account, fee);
    _participation(operation, account, tax);
    _participation(operation, account, cashDebit);
    _positive(gross);
    if (fee.minorUnits < BigInt.zero ||
        tax.minorUnits < BigInt.zero ||
        cashDebit.minorUnits <= BigInt.zero) {
      throw const LedgerException(LedgerError.invalidAmount);
    }
    if (id == investmentBuyId) {
      throw const LedgerException(LedgerError.duplicateIdentity);
    }
    final expectedDebit = gross.minorUnits + fee.minorUnits + tax.minorUnits;
    if (expectedDebit > Money.maxMinorUnits ||
        expectedDebit != cashDebit.minorUnits) {
      throw const LedgerException(LedgerError.investmentBuyMismatch);
    }
    return Posting._(
      id: id,
      operation: operation,
      date: date,
      kind: PostingKind.investmentBuy,
      legs: [LedgerLeg._(account, -cashDebit, LegRole.principal)],
      reportIncome: Money(account.currency, BigInt.zero),
      reportExpense: Money(account.currency, BigInt.zero),
      investmentBuy: InvestmentBuyCashDetails._(
        buyId: investmentBuyId,
        gross: gross,
        fee: fee,
        tax: tax,
        cashDebit: cashDebit,
      ),
    );
  }

  /// Credits settled cash exactly once. The application must atomically link
  /// this proposal to a validated investment disposition and its lot changes.
  factory Posting.investmentSell({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate date,
    required PostingAccount account,
    required PublicId investmentSellId,
    required Money gross,
    required Money fee,
    required Money tax,
    required Money cashCredit,
  }) {
    _participation(operation, account, gross);
    _participation(operation, account, fee);
    _participation(operation, account, tax);
    _participation(operation, account, cashCredit);
    _positive(gross);
    if (fee.minorUnits < BigInt.zero ||
        tax.minorUnits < BigInt.zero ||
        cashCredit.minorUnits <= BigInt.zero) {
      throw const LedgerException(LedgerError.invalidAmount);
    }
    if (id == investmentSellId) {
      throw const LedgerException(LedgerError.duplicateIdentity);
    }
    final expectedCredit = gross.minorUnits - fee.minorUnits - tax.minorUnits;
    if (expectedCredit <= BigInt.zero ||
        expectedCredit != cashCredit.minorUnits) {
      throw const LedgerException(LedgerError.investmentSellMismatch);
    }
    return Posting._(
      id: id,
      operation: operation,
      date: date,
      kind: PostingKind.investmentSell,
      legs: [LedgerLeg._(account, cashCredit, LegRole.principal)],
      reportIncome: Money(account.currency, BigInt.zero),
      reportExpense: Money(account.currency, BigInt.zero),
      investmentSell: InvestmentSellCashDetails._(
        sellId: investmentSellId,
        gross: gross,
        fee: fee,
        tax: tax,
        cashCredit: cashCredit,
      ),
    );
  }

  /// Credits the actual settlement account without claiming ordinary income.
  /// The application must atomically link a validated dividend fact.
  factory Posting.investmentDividend({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate date,
    required PostingAccount account,
    required PublicId investmentDividendId,
    required Money gross,
    required Money withholdingTax,
    required Money fee,
    required Money cashCredit,
  }) {
    _participation(operation, account, gross);
    _participation(operation, account, withholdingTax);
    _participation(operation, account, fee);
    _participation(operation, account, cashCredit);
    _positive(gross);
    if (withholdingTax.minorUnits < BigInt.zero ||
        fee.minorUnits < BigInt.zero ||
        cashCredit.minorUnits <= BigInt.zero) {
      throw const LedgerException(LedgerError.invalidAmount);
    }
    if (id == investmentDividendId) {
      throw const LedgerException(LedgerError.duplicateIdentity);
    }
    final expectedCredit =
        gross.minorUnits - withholdingTax.minorUnits - fee.minorUnits;
    if (expectedCredit <= BigInt.zero ||
        expectedCredit != cashCredit.minorUnits) {
      throw const LedgerException(LedgerError.investmentDividendMismatch);
    }
    return Posting._(
      id: id,
      operation: operation,
      date: date,
      kind: PostingKind.investmentDividend,
      legs: [LedgerLeg._(account, cashCredit, LegRole.principal)],
      reportIncome: Money(account.currency, BigInt.zero),
      reportExpense: Money(account.currency, BigInt.zero),
      investmentDividend: InvestmentDividendCashDetails._(
        dividendId: investmentDividendId,
        gross: gross,
        withholdingTax: withholdingTax,
        fee: fee,
        cashCredit: cashCredit,
      ),
    );
  }

  factory Posting.refund({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate date,
    required PostingAccount account,
    required PublicId originalId,
    required Money amount,
    Money? received,
    List<Allocation> allocations = const [],
  }) {
    final incoming = received ?? amount;
    _participation(operation, account, incoming);
    _positive(amount);
    _positive(incoming);
    _allocations(amount, allocations);
    if (id == originalId) {
      throw const LedgerException(LedgerError.refundReference);
    }
    final foreign = amount.currency != incoming.currency;
    if ((!foreign && incoming != amount) ||
        (foreign && amount.currency.code == incoming.currency.code)) {
      throw const LedgerException(LedgerError.currencyMismatch);
    }
    return Posting._(
      id: id,
      operation: operation,
      date: date,
      kind: PostingKind.refund,
      legs: [LedgerLeg._(account, incoming, LegRole.principal)],
      reportIncome: Money(amount.currency, BigInt.zero),
      reportExpense: -amount,
      allocations: allocations,
      refundOf: originalId,
      conversion: foreign ? ActualConversion(amount, incoming) : null,
    );
  }

  /// Retains the original and negates every cash/report effect exactly.
  /// Persistence revalidates the original and its dependent events atomically.
  /// An opening or a refund can be reversed too, so a wrong opening balance
  /// or a refund booked against the wrong expense has a correction path; a
  /// reversed refund gives its amount back to the original's refund limit.
  /// Investment cash postings are reversed only when their trade is voided:
  /// [tradeVoid] says the caller removes the trade in the same transaction.
  factory Posting.reversal({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate date,
    required Posting original,
    String reason = '',
    bool tradeVoid = false,
  }) {
    final allowed = switch (original.kind) {
      PostingKind.opening ||
      PostingKind.income ||
      PostingKind.expense ||
      PostingKind.transfer ||
      PostingKind.refund => true,
      PostingKind.investmentBuy ||
      PostingKind.investmentSell ||
      PostingKind.investmentDividend => tradeVoid,
      PostingKind.reversal => false,
    };
    if (!allowed ||
        id == original.id ||
        date.compareTo(original.date) < 0 ||
        reason != reason.trim() ||
        reason.runes.length > 256) {
      throw const LedgerException(LedgerError.reversalReference);
    }
    if (operation.workspace != original.operation.workspace) {
      throw const LedgerException(LedgerError.workspaceMismatch);
    }
    return Posting._(
      id: id,
      operation: operation,
      date: date,
      kind: PostingKind.reversal,
      legs: [
        for (final leg in original.legs)
          LedgerLeg._(leg.account, -leg.amount, leg.role),
      ],
      allocations: original.allocations,
      reportIncome: -original.reportIncome,
      reportExpense: -original.reportExpense,
      conversion: original.conversion,
      reversedPosting: original,
      reversalReason: reason,
    );
  }

  factory Posting.transfer({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate date,
    required PostingAccount source,
    required PostingAccount destination,
    required Money principal,
    Money? received,
    Money? fee,
  }) {
    final incoming = received ?? principal;
    _participation(operation, source, principal);
    _participation(operation, destination, incoming);
    _positive(principal);
    _positive(incoming);
    if (source.id == destination.id)
      throw const LedgerException(LedgerError.sameAccount);
    final cross = source.currency != destination.currency;
    if ((!cross && incoming != principal) ||
        (cross && source.currency.code == destination.currency.code))
      throw const LedgerException(LedgerError.currencyMismatch);
    final charge = fee ?? Money(source.currency, BigInt.zero);
    if (charge.currency != principal.currency)
      throw const LedgerException(LedgerError.currencyMismatch);
    if (charge.minorUnits < BigInt.zero)
      throw const LedgerException(LedgerError.invalidAmount);
    principal + charge;
    return Posting._(
      id: id,
      operation: operation,
      date: date,
      kind: PostingKind.transfer,
      legs: [
        LedgerLeg._(source, -principal, LegRole.principal),
        LedgerLeg._(destination, incoming, LegRole.principal),
        if (charge.minorUnits != BigInt.zero)
          LedgerLeg._(source, -charge, LegRole.fee),
      ],
      reportIncome: Money(source.currency, BigInt.zero),
      reportExpense: charge,
      conversion: cross ? ActualConversion(principal, incoming) : null,
    );
  }

  final PublicId id;
  final OperationKey operation;
  final BusinessDate date;
  final PostingKind kind;
  final List<LedgerLeg> legs;
  final List<Allocation> allocations;
  final Money reportIncome;
  final Money reportExpense;
  final ActualConversion? conversion;
  final PublicId? refundOf;
  final Posting? reversedPosting;
  final String? reversalReason;
  final InvestmentBuyCashDetails? investmentBuy;
  final InvestmentSellCashDetails? investmentSell;
  final InvestmentDividendCashDetails? investmentDividend;
  PublicId? get reversalOf => reversedPosting?.id;
}

void _participation(
  OperationKey operation,
  PostingAccount account,
  Money amount,
) {
  if (operation.workspace != account.workspace)
    throw const LedgerException(LedgerError.workspaceMismatch);
  if (amount.currency != account.currency)
    throw const LedgerException(LedgerError.currencyMismatch);
}

void _positive(Money amount) {
  if (amount.minorUnits <= BigInt.zero)
    throw const LedgerException(LedgerError.invalidAmount);
}

void _allocations(Money amount, List<Allocation> allocations) {
  if (allocations.isEmpty) return;
  var total = BigInt.zero;
  final categories = <PublicId>{};
  for (final allocation in allocations) {
    if (allocation.amount.currency != amount.currency)
      throw const LedgerException(LedgerError.currencyMismatch);
    if (!categories.add(allocation.categoryId))
      throw const LedgerException(LedgerError.duplicateIdentity);
    total += allocation.amount.minorUnits;
  }
  if (total != amount.minorUnits)
    throw const LedgerException(LedgerError.allocationMismatch);
}

/// Caller supplies the committed effective set, not drafts or superseded history.
Money rebuildBalance(PostingAccount account, Iterable<Posting> committed) {
  var total = BigInt.zero;
  final identities = <PublicId>{};
  final operations = <OperationKey>{};
  for (final posting in committed) {
    if (posting.operation.workspace != account.workspace)
      throw const LedgerException(LedgerError.workspaceMismatch);
    // A retried command must never be counted twice, even under a new id.
    if (!identities.add(posting.id) || !operations.add(posting.operation))
      throw const LedgerException(LedgerError.duplicateIdentity);
    for (final leg in posting.legs.where(
      (leg) => leg.account.id == account.id,
    )) {
      if (leg.amount.currency != account.currency)
        throw const LedgerException(LedgerError.currencyMismatch);
      total += leg.amount.minorUnits;
    }
  }
  return Money(account.currency, total);
}

/// Actual principals are authoritative. This is not a provider observation;
/// fees and presentation rounding never change its exact relationship.
final class ActualConversion {
  ActualConversion(Money sent, Money received)
    : rate = FxRate.fromAmounts(sent, received) {
    if (sent.currency.code == received.currency.code)
      throw const LedgerException(LedgerError.currencyMismatch);
  }
  final FxRate rate;
  Map<String, Object> toJson() => {
    'version': 1,
    'basis': 'actual-principals-v1',
    'rate': rate.toJson(),
  };
}
