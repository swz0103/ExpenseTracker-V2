import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'codec.dart';
import 'commands.dart';

/// What bookkeeping needs from storage inside one write transaction.
/// Implementations update their projections (balances, monthly totals) in
/// the same transaction as the event.
abstract interface class BookkeepingTransaction implements WriteTransaction {
  Future<Account?> account(PublicId id);

  Future<Posting?> posting(PublicId id);

  /// True once a reversal of [postingId] has been recorded.
  Future<bool> isReversed(PublicId postingId);

  Future<void> saveAccount(Account account);

  Future<void> savePosting(Posting posting);

  Future<void> appendEvent({
    required PublicId id,
    required WorkspaceId workspace,
    required String kind,
    required String payload,
  });
}

/// Runs account and posting commands. Every command commits its event, its
/// projections and its operation record together, or nothing.
final class Bookkeeping<T extends BookkeepingTransaction> {
  Bookkeeping(UnitOfWork<T> unitOfWork) : _runner = CommandRunner(unitOfWork);

  final CommandRunner<T> _runner;

  Future<CommandOutcome<int>> openAccount(OpenAccount command) =>
      _runner.run(command, (t) => _guard(() => _open(t, command)));

  Future<CommandOutcome<int>> renameAccount(RenameAccount command) =>
      _runner.run(command, (t) => _guard(() => _rename(t, command)));

  Future<CommandOutcome<int>> changeAccountState(ChangeAccountState command) =>
      _runner.run(command, (t) => _guard(() => _changeState(t, command)));

  Future<CommandOutcome<PublicId>> recordCashFlow(RecordCashFlow command) =>
      _runner.run(command, (t) => _guard(() => _cashFlow(t, command)));

  Future<CommandOutcome<PublicId>> recordTransfer(RecordTransfer command) =>
      _runner.run(command, (t) => _guard(() => _transfer(t, command)));

  Future<CommandOutcome<PublicId>> reversePosting(ReversePosting command) =>
      _runner.run(command, (t) => _guard(() => _reverse(t, command)));

  Future<int> _open(T t, OpenAccount command) async {
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
      await _savePosting(t, posting);
    }
    return account.version;
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

  Future<PublicId> _cashFlow(T t, RecordCashFlow command) async {
    await _requireNewPosting(t, command.postingId);
    final account = await _postable(
      t,
      command.account,
      command.operation.workspace,
      command.amount.currency,
      command.date,
    );
    final posting = switch (command.flow) {
      CashFlow.income => Posting.income(
        id: command.postingId,
        operation: command.operation,
        date: command.date,
        account: account,
        amount: command.amount,
      ),
      CashFlow.expense => Posting.expense(
        id: command.postingId,
        operation: command.operation,
        date: command.date,
        account: account,
        amount: command.amount,
      ),
    };
    await _savePosting(t, posting);
    return posting.id;
  }

  Future<PublicId> _transfer(T t, RecordTransfer command) async {
    await _requireNewPosting(t, command.postingId);
    final workspace = command.operation.workspace;
    final received = command.received ?? command.principal;
    final posting = Posting.transfer(
      id: command.postingId,
      operation: command.operation,
      date: command.date,
      source: await _postable(
        t,
        command.source,
        workspace,
        command.principal.currency,
        command.date,
      ),
      destination: await _postable(
        t,
        command.destination,
        workspace,
        received.currency,
        command.date,
      ),
      principal: command.principal,
      received: command.received,
      fee: command.fee,
    );
    await _savePosting(t, posting);
    return posting.id;
  }

  Future<PublicId> _reverse(T t, ReversePosting command) async {
    await _requireNewPosting(t, command.postingId);
    final original = await t.posting(command.originalId);
    if (original == null ||
        original.operation.workspace != command.operation.workspace) {
      throw const AppFailure(FailureKind.notFound, 'posting.not-found');
    }
    if (await t.isReversed(original.id)) {
      throw const AppFailure(FailureKind.conflict, 'posting.already-reversed');
    }
    // A closed account must keep its zero balance.
    for (final leg in original.legs) {
      final account = await _account(t, leg.account.id);
      if (account.state == AccountState.closed) {
        throw const AppFailure(FailureKind.rejected, 'account.unavailable');
      }
    }
    final reversal = Posting.reversal(
      id: command.postingId,
      operation: command.operation,
      date: command.date,
      original: original,
      reason: command.reason,
    );
    await _savePosting(t, reversal);
    return reversal.id;
  }

  Future<Account> _account(T t, PublicId id) async {
    final account = await t.account(id);
    if (account == null) {
      throw const AppFailure(FailureKind.notFound, 'account.not-found');
    }
    return account;
  }

  /// Checks the account rules in the same transaction as the ledger write.
  Future<PostingAccount> _postable(
    T t,
    AccountRef ref,
    WorkspaceId workspace,
    Currency currency,
    BusinessDate date,
  ) async {
    final account = await _account(t, ref.id);
    account.requirePosting(
      workspace: workspace,
      currency: currency,
      expectedVersion: ref.expectedVersion,
      date: date,
    );
    return _participant(account);
  }

  Future<void> _requireNewPosting(T t, PublicId id) async {
    if (await t.posting(id) != null) {
      throw const AppFailure(FailureKind.conflict, 'posting.exists');
    }
  }

  Future<void> _saveAccount(T t, Account account, String kind) async {
    await t.saveAccount(account);
    await t.appendEvent(
      id: PublicId.generate(),
      workspace: account.workspace,
      kind: kind,
      payload: jsonEncode(AccountCodec.encode(account)),
    );
  }

  Future<void> _savePosting(T t, Posting posting) async {
    await t.savePosting(posting);
    await t.appendEvent(
      id: PublicId.generate(),
      workspace: posting.operation.workspace,
      kind: 'posting.recorded',
      payload: jsonEncode(PostingCodec.encode(posting)),
    );
  }
}

PostingAccount _participant(Account account) => PostingAccount(
  id: account.id,
  workspace: account.workspace,
  currency: account.currency,
  expectedVersion: account.version,
);

/// Turns domain rule violations into typed failures with stable codes.
Future<R> _guard<R>(Future<R> Function() body) async {
  try {
    return await body();
  } on AccountException catch (error) {
    final kind = error.code == AccountError.versionConflict
        ? FailureKind.conflict
        : FailureKind.rejected;
    throw AppFailure(kind, 'account.${error.code.name}');
  } on LedgerException catch (error) {
    throw AppFailure(FailureKind.rejected, 'ledger.${error.code.name}');
  } on MoneyException catch (error) {
    throw AppFailure(FailureKind.rejected, 'money.${error.code.name}');
  }
}
