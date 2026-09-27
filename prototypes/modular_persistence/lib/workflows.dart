import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'adapters.dart';
import 'database.dart';
import 'operations.dart';
import 'categories_adapter.dart';
import 'tagged_posting.dart';

export 'operations.dart' show OperationConflict, CommitResult;

final class FinancialWorkflows {
  FinancialWorkflows(this.db, {String sourceContext = 'fixture-manual-v1'})
    : accounts = AccountsAdapter(db),
      ledger = LedgerAdapter(db, sourceContext: sourceContext);
  final ProbeDatabase db;
  final AccountsAdapter accounts;
  final LedgerAdapter ledger;

  Future<CommitResult> createAccount(
    Account account,
    Posting opening, {
    void Function(String)? checkpoint,
  }) {
    if (account.state != AccountState.active ||
        account.version != 1 ||
        opening.kind != PostingKind.opening ||
        opening.legs.single.account.id != account.id ||
        opening.operation.workspace != account.workspace ||
        opening.date != account.openedOn) {
      throw ArgumentError('Opening must describe the new active account.');
    }
    return _commit(
      opening.operation,
      jsonEncode([
        'create-v1',
        account.id.value,
        accountJson(account),
        postingInput(opening),
      ]),
      opening.id,
      () async {
        await accounts.insert(account);
        checkpoint?.call('account');
        await _validate(opening);
        await ledger.insert(opening, checkpoint: checkpoint);
        await _checkBalances(opening);
      },
      'account.open',
      checkpoint,
    );
  }

  Future<CommitResult> post(
    Posting posting, {
    Iterable<TagSelection> tags = const [],
    void Function(String)? checkpoint,
  }) {
    final selections = canonicalTags(tags);
    final input = postingInput(posting);
    return _commit(
      posting.operation,
      jsonEncode(
        selections.isEmpty
            ? input
            : [
                'tagged-post-v1',
                input,
                [
                  for (final tag in selections)
                    [tag.id.value, tag.expectedVersion],
                ],
              ],
      ),
      posting.id,
      () async {
        final categorySequence = await _validate(posting);
        final tagSequence = await validatePostingTags(db, posting, selections);
        await ledger.insert(
          posting,
          categorySequence: categorySequence,
          checkpoint: checkpoint,
        );
        await insertPostingTags(
          db,
          posting.operation.workspace,
          posting.id,
          selections,
          tagSequence,
        );
        if (selections.isNotEmpty) checkpoint?.call('tags');
        await _checkBalances(posting);
      },
      'ledger.${posting.kind.name}',
      checkpoint,
    );
  }

  Future<CommitResult> archive(
    WorkspaceId workspace,
    PublicId accountId,
    int version,
    OperationId operation,
  ) => _commit(
    OperationKey(workspace, operation),
    jsonEncode(['archive-v1', accountId.value, version]),
    accountId,
    () async {
      final account = await accounts.read(workspace, accountId);
      await accounts.replace(
        account.archive(workspace: workspace, expectedVersion: version),
      );
    },
    'account.archive',
    null,
  );

  Future<void> _checkBalances(Posting posting) async {
    final visited = <PublicId>{};
    for (final leg in posting.legs) {
      if (visited.add(leg.account.id)) await ledger.balance(leg.account);
    }
  }

  Future<int?> _validate(Posting posting) async {
    int? categorySequence;
    if (posting.allocations.isNotEmpty) {
      if (!db.categoryReferences) {
        throw UnsupportedError('Category references require schema 5.');
      }
      final categories = CategoriesAdapter(db);
      final catalog = await categories.read(posting.operation.workspace);
      for (final allocation in posting.allocations) {
        final version = allocation.expectedCategoryVersion;
        if (version == null)
          throw ArgumentError('Category version is required.');
        catalog.requireSelection(
          workspace: posting.operation.workspace,
          id: allocation.categoryId,
          expectedVersion: version,
          kind: posting.kind == PostingKind.income
              ? CategoryKind.income
              : CategoryKind.expense,
        );
      }
      categorySequence = await categories.currentSequence(
        posting.operation.workspace,
      );
    }
    for (final leg in posting.legs) {
      final account = await accounts.read(
        posting.operation.workspace,
        leg.account.id,
      );
      account.requirePosting(
        workspace: posting.operation.workspace,
        currency: leg.amount.currency,
        expectedVersion: leg.account.expectedVersion,
        date: posting.date,
      );
    }
    return categorySequence;
  }

  Future<CommitResult> _commit(
    OperationKey operation,
    String input,
    PublicId proposedId,
    Future<void> Function() write,
    String kind,
    void Function(String)? checkpoint,
  ) =>
      OperationWriter(db)
          .commit(operation, input, proposedId, write, kind, checkpoint);
}
