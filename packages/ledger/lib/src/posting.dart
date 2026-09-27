import 'package:foundation_values/foundation_values.dart';

part 'refund.dart';

enum PostingKind { opening, income, expense, transfer, refund }

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
  for (final posting in committed) {
    if (posting.operation.workspace != account.workspace)
      throw const LedgerException(LedgerError.workspaceMismatch);
    if (!identities.add(posting.id))
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
