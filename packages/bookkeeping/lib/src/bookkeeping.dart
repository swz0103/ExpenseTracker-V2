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

part 'account_handlers.dart';
part 'cards.dart';
part 'catalog_handlers.dart';
part 'correction_handlers.dart';
part 'entry_handlers.dart';
part 'investments.dart';
part 'planning.dart';

/// Tags and merchant attached to a posting. They never change amounts and
/// are stored beside the posting; a reversal carries the original's.
/// The currency reports, budgets and net worth are kept in. A foreign
/// entry counts at the value it had in it when booked (feature audit G-11).
final homeCurrency = Currency.of('TWD');

final class PostingMetadata {
  PostingMetadata({
    Iterable<PublicId> tags = const [],
    this.merchantId,
    this.homeValue,
  }) : tags = List.unmodifiable(
         {...tags}.toList()..sort((a, b) => a.value.compareTo(b.value)),
       ) {
    if (this.tags.length > 16) {
      throw const AppFailure(FailureKind.rejected, 'tag.limit');
    }
    final home = homeValue;
    if (home != null &&
        (home.currency != homeCurrency || home.minorUnits <= BigInt.zero)) {
      throw const AppFailure(FailureKind.rejected, 'posting.home-value');
    }
  }

  factory PostingMetadata.fromJson(Map<String, Object?> json) => decoding(() {
    checkKeys(json, const {'tags', 'merchantId', 'homeValue'});
    final tags = (json['tags'] as List).cast<String>();
    final merchant = json['merchantId'] as String?;
    final home = json['homeValue'] as Map<String, Object?>?;
    return PostingMetadata(
      tags: tags.map(PublicId.parse),
      merchantId: merchant == null ? null : PublicId.parse(merchant),
      homeValue: home == null ? null : Money.fromJson(home),
    );
  });

  static final none = PostingMetadata();

  final List<PublicId> tags;
  final PublicId? merchantId;

  /// What a foreign-currency entry was worth in [homeCurrency] when it was
  /// booked, as a positive amount.
  final Money? homeValue;

  /// The same tags and merchant with [homeValue] replaced.
  PostingMetadata withHomeValue(Money? homeValue) =>
      PostingMetadata(tags: tags, merchantId: merchantId, homeValue: homeValue);

  Map<String, Object?> toJson() => {
    'tags': [for (final tag in tags) tag.value],
    'merchantId': merchantId?.value,
    'homeValue': homeValue?.toJson(),
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

  Future<CommandOutcome<int>> setNetWorthInclusion(
    SetNetWorthInclusion command,
  ) => _runner.run(command, (t) => _guard(() => _setNetWorth(t, command)));

  Future<CommandOutcome<int>> changeOpeningDate(ChangeOpeningDate command) =>
      _runner.run(command, (t) => _guard(() => _moveOpening(t, command)));

  Future<CommandOutcome<int>> changeAccountState(ChangeAccountState command) =>
      _runner.run(command, (t) => _guard(() => _changeState(t, command)));

  Future<CommandOutcome<PublicId>> recordCashFlow(RecordCashFlow command) =>
      _runner.run(command, (t) => _guard(() => _cashFlow(t, command)));

  Future<CommandOutcome<PublicId>> adjustBalance(AdjustBalance command) =>
      _runner.run(command, (t) => _guard(() => _adjustBalance(t, command)));

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

  Future<CommandOutcome<PublicId>> correctTransfer(CorrectTransfer command) =>
      _runner.run(command, (t) => _guard(() => _correctTransfer(t, command)));

  Future<CommandOutcome<PublicId>> deletePosting(DeletePosting command) =>
      _runner.run(command, (t) => _guard(() => _delete(t, command)));

  Future<CommandOutcome<int>> closeAccount(CloseAccount command) =>
      _runner.run(command, (t) => _guard(() => _close(t, command)));

  Future<CommandOutcome<int>> changeCatalog(ChangeCatalog command) =>
      _runner.run(command, (t) => _guard(() => _catalog(t, command)));

  Future<Account> _account(T t, PublicId id) async {
    final account = await t.account(id);
    if (account == null) {
      throw const AppFailure(FailureKind.notFound, 'account.not-found');
    }
    return account;
  }

  /// Checks the account rules in the same transaction as the ledger write.
  /// A credit card takes postings only from its card commands ([card]),
  /// so its statement always matches its balance.
  Future<PostingAccount> _postable(
    T t,
    AccountRef ref,
    WorkspaceId workspace,
    Currency currency,
    BusinessDate date, {
    bool card = false,
  }) async {
    _requireBookable(date);
    final account = await _account(t, ref.id);
    account.requirePosting(
      workspace: workspace,
      currency: currency,
      expectedRulesVersion: ref.expectedVersion,
      date: date,
    );
    if (account.kind == AccountKind.creditCard && !card) {
      throw const AppFailure(FailureKind.rejected, 'card.use-card-commands');
    }
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
    _requireBookable(posting.date);
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
    MerchantSelection? merchant, {
    Money? homeValue,
    Currency? currency,
  }) async {
    // Only a foreign-currency entry has a home value (G-11).
    if (homeValue != null && currency == homeCurrency) {
      throw const AppFailure(FailureKind.rejected, 'posting.home-value');
    }
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
    return PostingMetadata(
      tags: ids,
      merchantId: merchant?.id,
      homeValue: homeValue,
    );
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

/// The first and last dates anything can be booked on; a date outside
/// them is a typo (feature audit G-18b). Date pickers use the same range.
final earliestBookingDate = BusinessDate(2000, 1, 1);
final latestBookingDate = BusinessDate(2099, 12, 31);

void _requireBookable(BusinessDate date) {
  if (date.compareTo(earliestBookingDate) < 0 ||
      date.compareTo(latestBookingDate) > 0) {
    throw const AppFailure(FailureKind.rejected, 'date.out-of-range');
  }
}
