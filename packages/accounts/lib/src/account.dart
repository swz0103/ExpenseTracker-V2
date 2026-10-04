import 'package:foundation_values/foundation_values.dart';

enum AccountKind {
  cash,
  bank,
  creditCard,

  /// Stored value such as LINE Pay Money or JKOPAY (feature audit G-20b).
  eWallet,

  /// A loan; its balance is negative while money is owed.
  loan,

  /// Money someone owes you, such as a bill you paid for a friend (代墊).
  /// Paying for them is a transfer into this account, not spending; their
  /// repayment is a transfer out of it, in part or in full, and what is
  /// never repaid is written off as an expense from it.
  receivable,

  /// Something valued by hand, such as a fund whose price is not fetched;
  /// its value is kept current with `AdjustBalance`.
  manual,
}

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
    required this.rulesVersion,
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
    rulesVersion: 1,
    state: AccountState.active,
  );

  /// Restore validated persisted state; never use to bypass a business transition.
  factory Account.restore({
    required PublicId id,
    required WorkspaceId workspace,
    required String name,
    required AccountKind kind,
    required Currency currency,
    required BusinessDate openedOn,
    required bool includeInNetWorth,
    required int version,
    required int rulesVersion,
    required AccountState state,
    BusinessDate? closedOn,
    String? closingReason,
    PublicId? successorId,
  }) {
    if (version < 1 ||
        rulesVersion < 1 ||
        rulesVersion > version ||
        (closedOn != null && closedOn.compareTo(openedOn) < 0) ||
        (state == AccountState.closed && closedOn == null) ||
        (closedOn == null && (closingReason != null || successorId != null)) ||
        (closedOn != null &&
            (closingReason == null ||
                closingReason.trim().isEmpty ||
                closingReason.length > 500)) ||
        successorId == id) {
      throw const AccountException(AccountError.invalidInput);
    }
    return Account._(
      id: id,
      workspace: workspace,
      name: _name(name),
      kind: kind,
      currency: currency,
      openedOn: openedOn,
      includeInNetWorth: includeInNetWorth,
      version: version,
      rulesVersion: rulesVersion,
      state: state,
      closedOn: closedOn,
      closingReason: closingReason,
      successorId: successorId,
    );
  }

  final PublicId id;
  final WorkspaceId workspace;
  final String name;
  final AccountKind kind;
  final Currency currency;
  final BusinessDate openedOn;
  final bool includeInNetWorth;

  /// Bumped by every change, for edits of the account itself.
  final int version;

  /// Bumped only when the rules for postings change (archive, close,
  /// reactivate), so a prepared entry survives a rename (health check
  /// G1-09).
  final int rulesVersion;
  final AccountState state;
  final BusinessDate? closedOn;
  final String? closingReason;
  final PublicId? successorId;

  /// Application must read this state in the same UoW as the Ledger write.
  /// [expectedRulesVersion] is the [rulesVersion] the entry was prepared
  /// against; renames and other edits do not invalidate it.
  void requirePosting({
    required WorkspaceId workspace,
    required Currency currency,
    required int expectedRulesVersion,
    required BusinessDate date,
  }) {
    if (workspace != this.workspace)
      throw const AccountException(AccountError.workspaceMismatch);
    if (expectedRulesVersion != rulesVersion)
      throw const AccountException(AccountError.versionConflict);
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

  /// Moves the opening date earlier, so entries from before the account
  /// was set up in the app can be recorded. Later dates are refused: an
  /// existing entry could fall before them.
  Account moveOpening({
    required WorkspaceId workspace,
    required int expectedVersion,
    required BusinessDate openedOn,
  }) {
    _check(workspace, expectedVersion);
    if (state == AccountState.closed)
      throw const AccountException(AccountError.unavailable);
    if (openedOn.compareTo(this.openedOn) > 0)
      throw const AccountException(AccountError.invalidDate);
    return Account._(
      id: id,
      workspace: workspace,
      name: name,
      kind: kind,
      currency: currency,
      openedOn: openedOn,
      includeInNetWorth: includeInNetWorth,
      version: version + 1,
      rulesVersion: rulesVersion,
      state: state,
      closedOn: closedOn,
      closingReason: closingReason,
      successorId: successorId,
    );
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
      rulesVersion: rulesVersion + 1,
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
    if (expectedVersion != version || version >= _maxSafeVersion) {
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
        rulesVersion: state == null ? rulesVersion : rulesVersion + 1,
        state: state ?? this.state,
        closedOn: closedOn,
        closingReason: closingReason,
        successorId: successorId,
      );
}

String _name(String value) {
  final result = cleanName(value);
  if (result == null) throw const AccountException(AccountError.invalidInput);
  return result;
}

/// The largest version that can still be incremented exactly on every
/// platform, including the web, where integers are doubles.
const _maxSafeVersion = 9007199254740991;
