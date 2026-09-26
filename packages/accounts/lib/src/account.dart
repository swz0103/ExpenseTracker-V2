import 'package:foundation_values/foundation_values.dart';

enum AccountKind { cash, bank }

enum AccountState { active, archived, closed }

enum AccountError {
  invalidInput,
  workspaceMismatch,
  currencyMismatch,
  versionConflict,
  unavailable,
  nonZeroBalance,
  unsettledItems,
  invalidDate,
}

final class AccountException implements Exception {
  const AccountException(this.code);
  final AccountError code;
  @override
  String toString() => 'AccountException(${code.name})';
}

/// Immutable domain state. Balances belong to Ledger, not this aggregate.
final class Account {
  Account._({
    required this.id,
    required this.workspace,
    required this.name,
    required this.kind,
    required this.currency,
    required this.openedOn,
    required this.includeInNetWorth,
    required this.version,
    required this.state,
    this.closedOn,
    this.closingReason,
    this.successorId,
  });

  factory Account.open({
    required PublicId id,
    required WorkspaceId workspace,
    required String name,
    required AccountKind kind,
    required Currency currency,
    required BusinessDate openedOn,
    bool includeInNetWorth = true,
  }) => Account._(
    id: id,
    workspace: workspace,
    name: _name(name),
    kind: kind,
    currency: currency,
    openedOn: openedOn,
    includeInNetWorth: includeInNetWorth,
    version: 1,
    state: AccountState.active,
  );

  final PublicId id;
  final WorkspaceId workspace;
  final String name;
  final AccountKind kind;
  final Currency currency;
  final BusinessDate openedOn;
  final bool includeInNetWorth;
  final int version;
  final AccountState state;
  final BusinessDate? closedOn;
  final String? closingReason;
  final PublicId? successorId;

  /// Application must read this state in the same UoW as the Ledger write.
  void requirePosting({
    required WorkspaceId workspace,
    required Currency currency,
    required int expectedVersion,
    required BusinessDate date,
  }) {
    _check(workspace, expectedVersion);
    if (this.currency != currency)
      throw const AccountException(AccountError.currencyMismatch);
    if (state != AccountState.active)
      throw const AccountException(AccountError.unavailable);
    if (date.compareTo(openedOn) < 0)
      throw const AccountException(AccountError.invalidDate);
  }

  Account rename({
    required WorkspaceId workspace,
    required int expectedVersion,
    required String name,
  }) {
    _check(workspace, expectedVersion);
    return _copy(name: _name(name));
  }

  Account setNetWorthInclusion({
    required WorkspaceId workspace,
    required int expectedVersion,
    required bool included,
  }) {
    _check(workspace, expectedVersion);
    return _copy(includeInNetWorth: included);
  }

  Account archive({
    required WorkspaceId workspace,
    required int expectedVersion,
  }) {
    _check(workspace, expectedVersion);
    if (state != AccountState.active)
      throw const AccountException(AccountError.unavailable);
    return _copy(state: AccountState.archived);
  }

  /// Current balance and unsettled status must come from the same write UoW.
  /// The application persists the old/new state and close reason in Audit.
  Account close({
    required WorkspaceId workspace,
    required int expectedVersion,
    required PublicId balanceAccountId,
    required Money currentBalance,
    required bool hasUnsettledItems,
    required BusinessDate date,
    required String reason,
    Account? successor,
  }) {
    _check(workspace, expectedVersion);
    if (state == AccountState.closed)
      throw const AccountException(AccountError.unavailable);
    if (balanceAccountId != id)
      throw const AccountException(AccountError.invalidInput);
    if (currentBalance.currency != currency)
      throw const AccountException(AccountError.currencyMismatch);
    if (currentBalance.minorUnits != BigInt.zero)
      throw const AccountException(AccountError.nonZeroBalance);
    if (hasUnsettledItems)
      throw const AccountException(AccountError.unsettledItems);
    if (date.compareTo(openedOn) < 0)
      throw const AccountException(AccountError.invalidDate);
    if (reason.trim().isEmpty || reason.length > 500)
      throw const AccountException(AccountError.invalidInput);
    if (successor != null) {
      if (successor.id == id)
        throw const AccountException(AccountError.invalidInput);
      if (successor.workspace != workspace)
        throw const AccountException(AccountError.workspaceMismatch);
      if (successor.state != AccountState.active)
        throw const AccountException(AccountError.unavailable);
      if (successor.openedOn.compareTo(date) > 0)
        throw const AccountException(AccountError.invalidDate);
    }
    return Account._(
      id: id,
      workspace: workspace,
      name: name,
      kind: kind,
      currency: currency,
      openedOn: openedOn,
      includeInNetWorth: includeInNetWorth,
      version: version + 1,
      state: AccountState.closed,
      closedOn: date,
      closingReason: reason.trim(),
      successorId: successor?.id,
    );
  }

  /// Keeps the most recent closure metadata; Audit retains every transition.
  Account reactivate({
    required WorkspaceId workspace,
    required int expectedVersion,
  }) {
    _check(workspace, expectedVersion);
    if (state == AccountState.active)
      throw const AccountException(AccountError.unavailable);
    return _copy(state: AccountState.active);
  }

  void _check(WorkspaceId requestedWorkspace, int expectedVersion) {
    if (requestedWorkspace != workspace)
      throw const AccountException(AccountError.workspaceMismatch);
    if (expectedVersion != version || version == 9223372036854775807) {
      throw const AccountException(AccountError.versionConflict);
    }
  }

  Account _copy({String? name, bool? includeInNetWorth, AccountState? state}) =>
      Account._(
        id: id,
        workspace: workspace,
        name: name ?? this.name,
        kind: kind,
        currency: currency,
        openedOn: openedOn,
        includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
        version: version + 1,
        state: state ?? this.state,
        closedOn: closedOn,
        closingReason: closingReason,
        successorId: successorId,
      );
}

String _name(String value) {
  final result = value.trim();
  if (result.isEmpty || result.length > 100)
    throw const AccountException(AccountError.invalidInput);
  return result;
}
