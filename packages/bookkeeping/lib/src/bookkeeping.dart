import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:budgets/budgets.dart';
import 'package:categories/categories.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:merchants/merchants.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:reports/reports.dart';
import 'package:tags/tags.dart';

import 'card_commands.dart';
import 'catalog_codec.dart';
import 'catalog_commands.dart';
import 'codec.dart';
import 'commands.dart';
import 'investment_commands.dart';
import 'planning_commands.dart';

part 'cards.dart';
part 'investments.dart';
part 'planning.dart';

/// Tags and merchant attached to a posting. They never change amounts and
/// are stored beside the posting; a reversal carries the original's.
final class PostingMetadata {
  PostingMetadata({Iterable<PublicId> tags = const [], this.merchantId})
    : tags = List.unmodifiable(
        {...tags}.toList()..sort((a, b) => a.value.compareTo(b.value)),
      ) {
    if (this.tags.length > 16) {
      throw const AppFailure(FailureKind.rejected, 'tag.limit');
    }
  }

  factory PostingMetadata.fromJson(Map<String, Object?> json) => decoding(() {
    checkKeys(json, const {'tags', 'merchantId'});
    final tags = (json['tags'] as List).cast<String>();
    final merchant = json['merchantId'] as String?;
    return PostingMetadata(
      tags: tags.map(PublicId.parse),
      merchantId: merchant == null ? null : PublicId.parse(merchant),
    );
  });

  static final none = PostingMetadata();

  final List<PublicId> tags;
  final PublicId? merchantId;

  Map<String, Object?> toJson() => {
    'tags': [for (final tag in tags) tag.value],
    'merchantId': merchantId?.value,
  };
}

/// What bookkeeping needs from storage inside one write transaction.
/// Implementations update their projections (balances, monthly totals) in
/// the same transaction as the event.
abstract interface class BookkeepingTransaction implements WriteTransaction {
  Future<Account?> account(PublicId id);

  Future<Posting?> posting(PublicId id);

  /// True once a reversal of [postingId] has been recorded.
  Future<bool> isReversed(PublicId postingId);

  /// True when another record (a card charge or payment) owns the posting;
  /// it must be corrected through that record instead of a plain reversal.
  Future<bool> isLocked(PublicId postingId);

  /// Refunds recorded against [expenseId], oldest first, including any
  /// that were later reversed.
  Future<List<Posting>> refundsOf(PublicId expenseId);

  /// The account's opening posting that has not been reversed, if any.
  Future<Posting?> openingOf(PublicId accountId);

  /// Revision 0 with empty text when the posting has no note.
  Future<EntryNote> noteOf(PublicId postingId);

  Future<void> saveNote(PublicId postingId, EntryNote note);

  Future<Money> balance(PublicId accountId, Currency currency);

  /// True while the account has pending card authorizations or funds an
  /// investment account with open lots.
  Future<bool> hasUnsettledItems(PublicId accountId);

  Future<void> saveAccount(Account account);

  Future<PostingMetadata> postingMetadata(PublicId postingId);

  Future<void> savePosting(Posting posting, PostingMetadata metadata);

  Future<List<Category>> categories(WorkspaceId workspace);

  Future<void> saveCategory(Category category);

  Future<List<Tag>> tags(WorkspaceId workspace);

  Future<void> saveTag(Tag tag);

  Future<List<Merchant>> merchants(WorkspaceId workspace);

  Future<void> saveMerchant(Merchant merchant);

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

  /// Runs [job] in the command queue with the store to itself, for work
  /// such as a backup.
  Future<R> exclusive<R>(Future<R> Function() job) => _runner.exclusive(job);

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

  Future<CommandOutcome<PublicId>> recordRefund(RecordRefund command) =>
      _runner.run(command, (t) => _guard(() => _refund(t, command)));

  Future<CommandOutcome<PublicId>> setOpeningBalance(
    SetOpeningBalance command,
  ) => _runner.run(command, (t) => _guard(() => _setOpening(t, command)));

  Future<CommandOutcome<int>> setNote(SetNote command) =>
      _runner.run(command, (t) => _guard(() => _note(t, command)));

  Future<CommandOutcome<PublicId>> correctCashFlow(CorrectCashFlow command) =>
      _runner.run(command, (t) => _guard(() => _correct(t, command)));

  Future<CommandOutcome<PublicId>> deletePosting(DeletePosting command) =>
      _runner.run(command, (t) => _guard(() => _delete(t, command)));

  Future<CommandOutcome<int>> closeAccount(CloseAccount command) =>
      _runner.run(command, (t) => _guard(() => _close(t, command)));

  Future<CommandOutcome<int>> changeCatalog(ChangeCatalog command) =>
      _runner.run(command, (t) => _guard(() => _catalog(t, command)));

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
      await _savePosting(t, posting, PostingMetadata.none);
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
    final workspace = command.operation.workspace;
    final account = await _postable(
      t,
      command.account,
      workspace,
      command.amount.currency,
      command.date,
    );
    final allocations = await _allocations(
      t,
      workspace,
      command.flow,
      command.allocations,
    );
    final metadata = await _metadata(
      t,
      workspace,
      command.tags,
      command.merchant,
    );
    final posting = switch (command.flow) {
      CashFlow.income => Posting.income(
        id: command.postingId,
        operation: command.operation,
        date: command.date,
        account: account,
        amount: command.amount,
        allocations: allocations,
      ),
      CashFlow.expense => Posting.expense(
        id: command.postingId,
        operation: command.operation,
        date: command.date,
        account: account,
        amount: command.amount,
        allocations: allocations,
      ),
    };
    await _savePosting(t, posting, metadata);
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
    await _savePosting(t, posting, PostingMetadata.none);
    return posting.id;
  }

  Future<PublicId> _reverse(T t, ReversePosting command) async {
    await _requireNewPosting(t, command.postingId);
    final original = await _reversible(t, command);
    final reversal = Posting.reversal(
      id: command.postingId,
      operation: command.operation,
      date: command.date,
      original: original,
      reason: command.reason,
    );
    await _savePosting(t, reversal, await t.postingMetadata(original.id));
    return reversal.id;
  }

  Future<PublicId> _delete(T t, DeletePosting command) async {
    await _requireNewPosting(t, command.postingId);
    final original = await _reversible(t, command);
    final reversal = Posting.reversal(
      id: command.postingId,
      operation: command.operation,
      date: original.date,
      original: original,
      reason: command.reason.isEmpty ? 'deleted' : command.reason,
    );
    await _savePosting(t, reversal, await t.postingMetadata(original.id));
    return reversal.id;
  }

  Future<PublicId> _correct(T t, CorrectCashFlow command) async {
    await _requireNewPosting(t, command.postingId);
    await _requireNewPosting(t, command.reversalId);
    final workspace = command.operation.workspace;
    final original = await _reversible(t, command);
    final flow = switch (original.kind) {
      PostingKind.income => CashFlow.income,
      PostingKind.expense => CashFlow.expense,
      _ => throw const AppFailure(
        FailureKind.rejected,
        'ledger.correctionReference',
      ),
    };
    final account = await _postable(
      t,
      command.account,
      workspace,
      command.amount.currency,
      command.date,
    );
    final allocations = await _allocations(
      t,
      workspace,
      flow,
      command.allocations,
    );
    final replacementOperation = _secondary(
      command.operation,
      command.postingId,
    );
    final replacement = flow == CashFlow.income
        ? Posting.income(
            id: command.postingId,
            operation: replacementOperation,
            date: command.date,
            account: account,
            amount: command.amount,
            allocations: allocations,
          )
        : Posting.expense(
            id: command.postingId,
            operation: replacementOperation,
            date: command.date,
            account: account,
            amount: command.amount,
            allocations: allocations,
          );
    final correction = PostingCorrection(
      original: original,
      replacement: replacement,
      reversalId: command.reversalId,
      reversalOperation: _secondary(command.operation, command.reversalId),
      reason: command.reason,
    );
    await _savePosting(
      t,
      correction.reversal,
      await t.postingMetadata(original.id),
    );
    await _savePosting(
      t,
      replacement,
      await _metadata(t, workspace, command.tags, command.merchant),
    );
    return replacement.id;
  }

  Future<int> _note(T t, SetNote command) async {
    final posting = await t.posting(command.postingId);
    if (posting == null ||
        posting.operation.workspace != command.operation.workspace) {
      throw const AppFailure(FailureKind.notFound, 'posting.not-found');
    }
    final note = NoteChange(
      command.postingId,
      command.expectedRevision,
      command.text,
    ).apply(await t.noteOf(command.postingId));
    await t.saveNote(command.postingId, note);
    await t.appendEvent(
      id: PublicId.generate(),
      workspace: command.operation.workspace,
      kind: 'posting.noted',
      payload: jsonEncode({
        'postingId': command.postingId.value,
        'revision': note.revision,
        'text': note.text,
      }),
    );
    return note.revision;
  }

  /// Reverses a posting its card or trade owns, on the posting's own date.
  Future<PublicId> _reverseOwned(
    T t,
    OperationKey operation,
    PublicId reversalId,
    PublicId postingId,
  ) async {
    await _requireNewPosting(t, reversalId);
    final original = await _undoable(
      t,
      operation.workspace,
      postingId,
      owned: true,
    );
    final reversal = Posting.reversal(
      id: reversalId,
      operation: operation,
      date: original.date,
      original: original,
      reason: 'voided',
      tradeVoid: true,
    );
    await _savePosting(t, reversal, await t.postingMetadata(original.id));
    return reversal.id;
  }

  /// The checks every undo path shares: the posting exists in this
  /// workspace, is not reversed yet, is not owned by a card or trade, has
  /// no active refunds, and touches no closed account.
  Future<Posting> _reversible(T t, Command<Object?> command) {
    final originalId = switch (command) {
      ReversePosting(:final originalId) => originalId,
      DeletePosting(:final originalId) => originalId,
      CorrectCashFlow(:final originalId) => originalId,
      _ => throw StateError('Not an undo command.'),
    };
    return _undoable(t, command.operation.workspace, originalId);
  }

  /// [owned] is true when the card or trade that owns the posting undoes it
  /// itself; everyone else is refused.
  Future<Posting> _undoable(
    T t,
    WorkspaceId workspace,
    PublicId originalId, {
    bool owned = false,
  }) async {
    final original = await t.posting(originalId);
    if (original == null || original.operation.workspace != workspace) {
      throw const AppFailure(FailureKind.notFound, 'posting.not-found');
    }
    if (await t.isReversed(original.id)) {
      throw const AppFailure(FailureKind.conflict, 'posting.already-reversed');
    }
    if (!owned && await t.isLocked(original.id)) {
      throw const AppFailure(FailureKind.rejected, 'posting.owned-elsewhere');
    }
    if ((await _activeRefunds(t, original.id)).isNotEmpty) {
      throw const AppFailure(FailureKind.rejected, 'posting.has-refunds');
    }
    // A closed account must keep its zero balance.
    for (final leg in original.legs) {
      final account = await _account(t, leg.account.id);
      if (account.state == AccountState.closed) {
        throw const AppFailure(FailureKind.rejected, 'account.unavailable');
      }
    }
    return original;
  }

  Future<PublicId> _refund(
    T t,
    RecordRefund command, {
    bool owned = false,
  }) async {
    await _requireNewPosting(t, command.postingId);
    final workspace = command.operation.workspace;
    final original = await t.posting(command.originalId);
    if (original == null || original.operation.workspace != workspace) {
      throw const AppFailure(FailureKind.notFound, 'posting.not-found');
    }
    if (original.kind != PostingKind.expense) {
      throw const AppFailure(FailureKind.rejected, 'ledger.refundReference');
    }
    if (await t.isReversed(original.id)) {
      throw const AppFailure(FailureKind.rejected, 'posting.already-reversed');
    }
    if (!owned && await t.isLocked(original.id)) {
      throw const AppFailure(FailureKind.rejected, 'posting.owned-elsewhere');
    }
    // The remaining refund authority is replayed from earlier refunds.
    var budget = RefundBudget(
      originalId: original.id,
      originalDate: original.date,
      amount: original.reportExpense,
      allocations: original.allocations,
    );
    for (final earlier in await _activeRefunds(t, original.id)) {
      budget = budget.consume(
        amount: -earlier.reportExpense,
        date: earlier.date,
        allocations: earlier.allocations,
      );
    }
    final allocations = [
      for (final share in command.allocations)
        Allocation(
          share.categoryId,
          share.amount,
          expectedCategoryVersion: share.expectedVersion,
        ),
    ];
    budget.consume(
      amount: command.amount,
      date: command.date,
      allocations: allocations,
    );
    final received = command.received ?? command.amount;
    final posting = Posting.refund(
      id: command.postingId,
      operation: command.operation,
      date: command.date,
      account: await _postable(
        t,
        command.account,
        workspace,
        received.currency,
        command.date,
      ),
      originalId: original.id,
      amount: command.amount,
      received: command.received,
      allocations: allocations,
    );
    await _savePosting(t, posting, await t.postingMetadata(original.id));
    return posting.id;
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

  Future<List<Posting>> _activeRefunds(T t, PublicId expenseId) async => [
    for (final refund in await t.refundsOf(expenseId))
      if (!await t.isReversed(refund.id)) refund,
  ];

  Future<int> _close(T t, CloseAccount command) async {
    final workspace = command.operation.workspace;
    final account = await _account(t, command.accountId);
    final successorId = command.successorId;
    final closed = account.close(
      workspace: workspace,
      expectedVersion: command.expectedVersion,
      balanceAccountId: account.id,
      currentBalance: await t.balance(account.id, account.currency),
      hasUnsettledItems: await t.hasUnsettledItems(account.id),
      date: command.date,
      reason: command.reason,
      successor: successorId == null ? null : await _account(t, successorId),
    );
    await _saveAccount(t, closed, 'account.closed');
    return closed.version;
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
      expectedRulesVersion: ref.expectedVersion,
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

  Future<void> _savePosting(
    T t,
    Posting posting,
    PostingMetadata metadata,
  ) async {
    await t.savePosting(posting, metadata);
    await t.appendEvent(
      id: PublicId.generate(),
      workspace: posting.operation.workspace,
      kind: 'posting.recorded',
      payload: jsonEncode({
        'posting': PostingCodec.encode(posting),
        'metadata': metadata.toJson(),
      }),
    );
  }

  /// Checks every category in the write transaction, at the version shown.
  Future<List<Allocation>> _allocations(
    T t,
    WorkspaceId workspace,
    CashFlow flow,
    List<CategoryShare> shares,
  ) async {
    if (shares.isEmpty) return const [];
    final catalog = CategoryCatalog.restore(
      workspace,
      await t.categories(workspace),
    );
    final kind = flow == CashFlow.income
        ? CategoryKind.income
        : CategoryKind.expense;
    return [
      for (final share in shares) _allocation(catalog, workspace, kind, share),
    ];
  }

  Allocation _allocation(
    CategoryCatalog catalog,
    WorkspaceId workspace,
    CategoryKind kind,
    CategoryShare share,
  ) {
    catalog.requireSelection(
      workspace: workspace,
      id: share.categoryId,
      kind: kind,
      expectedVersion: share.expectedVersion,
    );
    return Allocation(
      share.categoryId,
      share.amount,
      expectedCategoryVersion: share.expectedVersion,
    );
  }

  Future<PostingMetadata> _metadata(
    T t,
    WorkspaceId workspace,
    List<TagSelection> selected,
    MerchantSelection? merchant,
  ) async {
    if (selected.isNotEmpty) {
      final tags = TagCatalog.restore(workspace, await t.tags(workspace));
      for (final tag in selected) {
        tags.requireSelection(
          workspace: workspace,
          id: tag.id,
          expectedVersion: tag.expectedVersion,
        );
      }
    }
    if (merchant != null) {
      final merchants = MerchantCatalog.restore(
        workspace,
        await t.merchants(workspace),
      );
      merchants.requireSelection(
        workspace: workspace,
        id: merchant.id,
        expectedVersion: merchant.expectedVersion,
      );
    }
    final ids = [for (final tag in selected) tag.id];
    if (ids.toSet().length != ids.length) {
      throw const AppFailure(FailureKind.rejected, 'tag.duplicate');
    }
    return PostingMetadata(tags: ids, merchantId: merchant?.id);
  }

  Future<int> _catalog(T t, ChangeCatalog command) async {
    final workspace = command.operation.workspace;
    final change = command.change;
    switch (command.catalog) {
      case CatalogType.category:
        final before = await t.categories(workspace);
        final catalog = CategoryCatalog.restore(workspace, before);
        final after = _changeCategories(catalog, workspace, change).categories;
        return _commitCatalog(
          t,
          before: {for (final row in before) row.id: row.version},
          after: {for (final row in after) row.id: (row, row.version)},
          subject: change.subject,
          workspace: workspace,
          save: t.saveCategory,
          encode: CatalogCodec.category,
          kind: 'category.changed',
        );
      case CatalogType.tag:
        final before = await t.tags(workspace);
        final catalog = TagCatalog.restore(workspace, before);
        final after = _changeTags(catalog, workspace, change).tags;
        return _commitCatalog(
          t,
          before: {for (final row in before) row.id: row.version},
          after: {for (final row in after) row.id: (row, row.version)},
          subject: change.subject,
          workspace: workspace,
          save: t.saveTag,
          encode: CatalogCodec.tag,
          kind: 'tag.changed',
        );
      case CatalogType.merchant:
        final before = await t.merchants(workspace);
        final catalog = MerchantCatalog.restore(workspace, before);
        final after = _changeMerchants(catalog, workspace, change).merchants;
        return _commitCatalog(
          t,
          before: {for (final row in before) row.id: row.version},
          after: {for (final row in after) row.id: (row, row.version)},
          subject: change.subject,
          workspace: workspace,
          save: t.saveMerchant,
          encode: CatalogCodec.merchant,
          kind: 'merchant.changed',
        );
    }
  }

  /// Saves and journals every row whose version moved.
  Future<int> _commitCatalog<R>(
    T t, {
    required Map<PublicId, int> before,
    required Map<PublicId, (R, int)> after,
    required PublicId subject,
    required WorkspaceId workspace,
    required Future<void> Function(R row) save,
    required Map<String, Object?> Function(R row) encode,
    required String kind,
  }) async {
    for (final entry in after.entries) {
      final (row, version) = entry.value;
      if (before[entry.key] == version) continue;
      await save(row);
      await t.appendEvent(
        id: PublicId.generate(),
        workspace: workspace,
        kind: kind,
        payload: jsonEncode(encode(row)),
      );
    }
    return after[subject]!.$2;
  }
}

CategoryCatalog _changeCategories(
  CategoryCatalog catalog,
  WorkspaceId workspace,
  CatalogChange change,
) => switch (change) {
  CreateEntry(:final id, :final name, :final kind?, :final parentId) =>
    catalog.create(
      workspace: workspace,
      id: id,
      name: name,
      kind: kind,
      parentId: parentId,
    ),
  RenameEntry(:final id, :final expectedVersion, :final name) => catalog.rename(
    workspace: workspace,
    id: id,
    expectedVersion: expectedVersion,
    name: name,
  ),
  ArchiveEntry(:final id, :final expectedVersion, :final archived) =>
    catalog.setArchived(
      workspace: workspace,
      id: id,
      expectedVersion: expectedVersion,
      archived: archived,
    ),
  MergeEntry merge => catalog.merge(
    workspace: workspace,
    sourceId: merge.sourceId,
    expectedSourceVersion: merge.expectedSourceVersion,
    targetId: merge.targetId,
    expectedTargetVersion: merge.expectedTargetVersion,
  ),
  MoveCategory(:final id, :final expectedVersion, :final parentId) =>
    catalog.move(
      workspace: workspace,
      id: id,
      expectedVersion: expectedVersion,
      parentId: parentId,
    ),
  _ => throw const AppFailure(FailureKind.rejected, 'catalog.unsupported'),
};

TagCatalog _changeTags(
  TagCatalog catalog,
  WorkspaceId workspace,
  CatalogChange change,
) => switch (change) {
  CreateEntry(:final id, :final name, kind: null, parentId: null) =>
    catalog.create(workspace: workspace, id: id, name: name),
  RenameEntry(:final id, :final expectedVersion, :final name) => catalog.rename(
    workspace: workspace,
    id: id,
    expectedVersion: expectedVersion,
    name: name,
  ),
  ArchiveEntry(:final id, :final expectedVersion, :final archived) =>
    catalog.setArchived(
      workspace: workspace,
      id: id,
      expectedVersion: expectedVersion,
      archived: archived,
    ),
  MergeEntry merge => catalog.merge(
    workspace: workspace,
    sourceId: merge.sourceId,
    expectedSourceVersion: merge.expectedSourceVersion,
    targetId: merge.targetId,
    expectedTargetVersion: merge.expectedTargetVersion,
  ),
  _ => throw const AppFailure(FailureKind.rejected, 'catalog.unsupported'),
};

MerchantCatalog _changeMerchants(
  MerchantCatalog catalog,
  WorkspaceId workspace,
  CatalogChange change,
) => switch (change) {
  CreateEntry(:final id, :final name, kind: null, parentId: null) =>
    catalog.create(workspace: workspace, id: id, name: name),
  RenameEntry(:final id, :final expectedVersion, :final name) => catalog.rename(
    workspace: workspace,
    id: id,
    expectedVersion: expectedVersion,
    name: name,
  ),
  ArchiveEntry(:final id, :final expectedVersion, :final archived) =>
    catalog.setArchived(
      workspace: workspace,
      id: id,
      expectedVersion: expectedVersion,
      archived: archived,
    ),
  MergeEntry merge => catalog.merge(
    workspace: workspace,
    sourceId: merge.sourceId,
    expectedSourceVersion: merge.expectedSourceVersion,
    targetId: merge.targetId,
    expectedTargetVersion: merge.expectedTargetVersion,
  ),
  ChangeAlias(:final id, :final expectedVersion, :final alias, :final add) =>
    add
        ? catalog.addAlias(
            workspace: workspace,
            id: id,
            expectedVersion: expectedVersion,
            alias: alias,
          )
        : catalog.removeAlias(
            workspace: workspace,
            id: id,
            expectedVersion: expectedVersion,
            alias: alias,
          ),
  _ => throw const AppFailure(FailureKind.rejected, 'catalog.unsupported'),
};

/// The identity of a second posting made by one command. Every posting
/// needs its own OperationKey; deriving it from the posting's own id keeps
/// it unique and stable across retries.
OperationKey _secondary(OperationKey command, PublicId postingId) =>
    OperationKey(command.workspace, OperationId(postingId));

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
  } on NoteException catch (error) {
    final kind = error.code == NoteError.conflict
        ? FailureKind.conflict
        : FailureKind.rejected;
    throw AppFailure(kind, 'note.${error.code.name}');
  } on MoneyException catch (error) {
    throw AppFailure(FailureKind.rejected, 'money.${error.code.name}');
  } on InvestmentException catch (error) {
    throw AppFailure(FailureKind.rejected, 'investment.${error.code.name}');
  } on InvestmentSellException catch (error) {
    final kind = error.code == InvestmentSellError.staleLots
        ? FailureKind.conflict
        : FailureKind.rejected;
    throw AppFailure(kind, 'investment.${error.code.name}');
  } on StockSplitException catch (error) {
    final kind = error.code == StockSplitError.staleLots
        ? FailureKind.conflict
        : FailureKind.rejected;
    throw AppFailure(kind, 'split.${error.code.name}');
  } on InvestmentDividendException catch (error) {
    throw AppFailure(FailureKind.rejected, 'dividend.${error.code.name}');
  } on CreditCardException catch (error) {
    throw AppFailure(FailureKind.rejected, 'card.${error.code.name}');
  } on CategoryException catch (error) {
    throw _catalogFailure('category', error.code.name);
  } on TagException catch (error) {
    throw _catalogFailure('tag', error.code.name);
  } on MerchantException catch (error) {
    throw _catalogFailure('merchant', error.code.name);
  }
}

AppFailure _catalogFailure(String area, String code) {
  final kind = switch (code) {
    'versionConflict' => FailureKind.conflict,
    'missing' => FailureKind.notFound,
    _ => FailureKind.rejected,
  };
  return AppFailure(kind, '$area.$code');
}
