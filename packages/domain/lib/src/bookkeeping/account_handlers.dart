part of 'bookkeeping.dart';

/// Opening, renaming and archiving accounts, and their opening balance.
extension _Accounts<T extends BookkeepingTransaction> on Bookkeeping<T> {
  Future<int> _open(T t, OpenAccount command) async {
    _requireBookable(command.openedOn);
    if (await t.account(command.accountId) != null) {
      throw const AppFailure(FailureKind.conflict, 'account.exists');
    }
    final account = Account.open(
      id: command.accountId,
      workspace: command.operation.workspace,
      name: command.name,
      kind: command.kind,
      currency: command.currency,
      openedOn: command.openedOn,
      includeInNetWorth: command.includeInNetWorth,
    );
    await _saveAccount(t, account, 'account.opened');
    final balance = command.openingBalance;
    if (balance != null) {
      final posting = Posting.opening(
        id: command.openingPostingId!,
        operation: command.operation,
        date: command.openedOn,
        account: _participant(account),
        amount: balance,
      );
      await _savePosting(t, posting, PostingMetadata.none);
    }
    return account.version;
  }

  Future<int> _setNetWorth(T t, SetNetWorthInclusion command) async {
    final account = await _account(t, command.accountId);
    final changed = account.setNetWorthInclusion(
      workspace: command.operation.workspace,
      expectedVersion: command.expectedVersion,
      included: command.included,
    );
    await _saveAccount(t, changed, 'account.changed');
    return changed.version;
  }

  Future<int> _rename(T t, RenameAccount command) async {
    final account = await _account(t, command.accountId);
    final renamed = account.rename(
      workspace: command.operation.workspace,
      expectedVersion: command.expectedVersion,
      name: command.name,
    );
    await _saveAccount(t, renamed, 'account.renamed');
    return renamed.version;
  }

  Future<int> _changeState(T t, ChangeAccountState command) async {
    final account = await _account(t, command.accountId);
    final workspace = command.operation.workspace;
    final version = command.expectedVersion;
    final changed = switch (command.change) {
      AccountStateChange.archive => account.archive(
        workspace: workspace,
        expectedVersion: version,
      ),
      AccountStateChange.reactivate => account.reactivate(
        workspace: workspace,
        expectedVersion: version,
      ),
    };
    await _saveAccount(t, changed, 'account.${command.change.name}d');
    return changed.version;
  }

  /// Replaces the opening balance: the current opening (if any) is reversed
  /// and a new one is posted on the opening date, in one transaction.
  Future<PublicId> _setOpening(T t, SetOpeningBalance command) async {
    await _requireNewPosting(t, command.postingId);
    await _requireNewPosting(t, command.reversalId);
    final account = await _account(t, command.accountId);
    if (account.state == AccountState.closed) {
      throw const AppFailure(FailureKind.rejected, 'account.unavailable');
    }
    final participant = PostingAccount(
      id: account.id,
      workspace: account.workspace,
      currency: account.currency,
      expectedVersion: account.version,
    );
    account.requirePosting(
      workspace: command.operation.workspace,
      currency: command.amount.currency,
      expectedRulesVersion: command.expectedVersion,
      date: account.openedOn,
    );
    final current = await t.openingOf(account.id);
    if (current != null) {
      final reversal = Posting.reversal(
        id: command.reversalId,
        operation: _secondary(command.operation, command.reversalId),
        date: account.openedOn,
        original: current,
        reason: 'opening-balance-replaced',
      );
      await _savePosting(t, reversal, PostingMetadata.none);
    }
    final opening = Posting.opening(
      id: command.postingId,
      operation: command.operation,
      date: account.openedOn,
      account: participant,
      amount: command.amount,
    );
    await _savePosting(t, opening, PostingMetadata.none);
    return opening.id;
  }
}
