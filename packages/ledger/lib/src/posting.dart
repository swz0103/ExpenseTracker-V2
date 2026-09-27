import 'package:foundation_values/foundation_values.dart';

enum PostingKind { opening, income, expense, transfer }

enum LegRole { principal, fee }

enum LedgerError {
  invalidAmount,
  workspaceMismatch,
  currencyMismatch,
  sameAccount,
  allocationMismatch,
  duplicateIdentity,
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

  factory Posting.transfer({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate date,
    required PostingAccount source,
    required PostingAccount destination,
    required Money principal,
    Money? fee,
  }) {
    _participation(operation, source, principal);
    _participation(operation, destination, principal);
    _positive(principal);
    if (source.id == destination.id)
      throw const LedgerException(LedgerError.sameAccount);
    final charge = fee ?? Money(source.currency, BigInt.zero);
    if (charge.currency != principal.currency)
      throw const LedgerException(LedgerError.currencyMismatch);
    if (charge.minorUnits < BigInt.zero)
      throw const LedgerException(LedgerError.invalidAmount);
    // The combined source movement must also fit the persisted amount range.
    principal + charge;
    return Posting._(
      id: id,
      operation: operation,
      date: date,
      kind: PostingKind.transfer,
      legs: [
        LedgerLeg._(source, -principal, LegRole.principal),
        LedgerLeg._(destination, principal, LegRole.principal),
        if (charge.minorUnits != BigInt.zero)
          LedgerLeg._(source, -charge, LegRole.fee),
      ],
      reportIncome: Money(source.currency, BigInt.zero),
      reportExpense: charge,
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
