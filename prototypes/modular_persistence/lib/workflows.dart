import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:accounts/accounts.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'adapters.dart';
import 'database.dart';
import 'operations.dart';
import 'categories_adapter.dart';
import 'tagged_posting.dart';
import 'merchant_posting.dart';
import 'refunds_adapter.dart';
import 'reversals_adapter.dart';
import 'card_revisions_adapter.dart';

export 'operations.dart' show OperationConflict, CommitResult;

final class CorrectionCommitResult {
  const CorrectionCommitResult(
    this.reversalId,
    this.replacementId, {
    required this.replayed,
  });

  final PublicId reversalId;
  final PublicId replacementId;
  final bool replayed;
}

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
    CreditCardTerms? cardTerms,
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
    if ((account.kind == AccountKind.creditCard) != (cardTerms != null) ||
        (cardTerms != null &&
            (!db.creditCardsAware ||
                cardTerms.workspace != account.workspace ||
                cardTerms.cardId != account.id ||
                cardTerms.currency != account.currency ||
                cardTerms.version != 1))) {
      throw ArgumentError(
        'Credit-card opening requires matching schema 17 terms.',
      );
    }
    return _commit(
      opening.operation,
      jsonEncode(
        cardTerms == null
            ? [
                'create-v1',
                account.id.value,
                accountJson(account),
                postingInput(opening),
              ]
            : [
                'card-create-v1',
                account.id.value,
                accountJson(account),
                postingInput(opening),
                const CreditCardTermsCodec().encode(cardTerms),
              ],
      ),
      opening.id,
      () async {
        await accounts.insert(account);
        checkpoint?.call('account');
        await _validate(opening);
        await ledger.insert(opening, checkpoint: checkpoint);
        await _checkBalances(opening);
        if (cardTerms != null) {
          await appendCardTermsRevision(
            db,
            cardTerms,
            opening.operation.operation,
            DateTime.now().toUtc(),
          );
        }
      },
      'account.open',
      checkpoint,
    );
  }

  Future<CommitResult> post(
    Posting posting, {
    Iterable<TagSelection> tags = const [],
    MerchantSelection? merchant,
    void Function(String)? checkpoint,
  }) {
    if (posting.kind == PostingKind.investmentBuy) {
      throw UnsupportedError('Use the atomic investment buy workflow');
    }
    return _post(
      posting,
      tags: tags,
      merchant: merchant,
      checkpoint: checkpoint,
    );
  }

  Future<CommitResult> _post(
    Posting posting, {
    Iterable<TagSelection> tags = const [],
    MerchantSelection? merchant,
    void Function(String)? checkpoint,
    ({PostingCorrection pair, String role})? correctionReceipt,
  }) {
    final selections = canonicalTags(tags);
    final input = postingInput(posting);
    final tagged = selections.isEmpty
        ? input
        : [
            'tagged-post-v1',
            input,
            [
              for (final tag in selections) [tag.id.value, tag.expectedVersion],
            ],
          ];
    final selected = merchant == null
        ? tagged
        : [
            'merchant-post-v1',
            tagged,
            [
              [merchant.id.value, merchant.expectedVersion],
            ],
          ];
    final pair = correctionReceipt?.pair;
    final receiptInput = pair == null
        ? selected
        : [
            'correction-event-v1',
            pair.original.id.value,
            pair.reversal.id.value,
            pair.replacement.id.value,
            correctionReceipt!.role,
            selected,
          ];
    return _commit(
      posting.operation,
      jsonEncode(receiptInput),
      posting.id,
      () async {
        final refund = posting.refundOf == null
            ? null
            : await validateRefundPosting(db, posting, selections, merchant);
        final reversal = posting.reversalOf == null
            ? null
            : await validateReversalPosting(db, posting, selections, merchant);
        final categorySequence = await _validate(
          posting,
          refundSequence:
              refund?.categorySequence ?? reversal?.categorySequence,
        );
        final tagSequence = reversal != null
            ? reversal.tagSequence
            : refund != null
            ? refund.tagSequence
            : await validatePostingTags(db, posting, selections);
        final merchantSequence = reversal != null
            ? reversal.merchantSequence
            : refund != null
            ? refund.merchantSequence
            : await validatePostingMerchant(db, posting, merchant);
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
        await insertPostingMerchant(
          db,
          posting.operation.workspace,
          posting.id,
          merchant,
          merchantSequence,
        );
        if (merchant != null) checkpoint?.call('merchant');
        await _checkBalances(posting);
      },
      'ledger.${posting.kind.name}',
      checkpoint,
    );
  }

  /// The two financial receipts and their unique source link are one write.
  /// An independently committed reversal or replacement is never a replay.
  Future<CorrectionCommitResult> correct(
    PostingCorrection correction, {
    Iterable<TagSelection> replacementTags = const [],
    MerchantSelection? replacementMerchant,
    void Function(String)? checkpoint,
  }) async {
    if (!db.correctionsAware) {
      throw UnsupportedError('Corrections require schema 13.');
    }
    final original = correction.original;
    final reversal = correction.reversal;
    final replacement = correction.replacement;
    final workspace = original.operation.workspace;
    final ws = workspace.toString();
    final selections = canonicalTags(replacementTags);
    return db.transaction(() async {
      final link = await db
          .customSelect(
            'SELECT reversal_id,replacement_id FROM event_corrections WHERE workspace=? AND original_id=?',
            variables: [
              Variable.withString(ws),
              Variable.withString(original.id.value),
            ],
          )
          .getSingleOrNull();
      final reversalReceipt = await _correctionReceipt(
        ws,
        reversal.operation.operation.toString(),
      );
      final replacementReceipt = await _correctionReceipt(
        ws,
        replacement.operation.operation.toString(),
      );
      if (link == null) {
        if (reversalReceipt != null || replacementReceipt != null) {
          throw OperationConflict();
        }
      } else {
        if (link.read<String>('reversal_id') != reversal.id.value ||
            link.read<String>('replacement_id') != replacement.id.value ||
            !_matchingCorrectionReceipt(
              reversalReceipt,
              reversal,
              'ledger.reversal',
            ) ||
            !_matchingCorrectionReceipt(
              replacementReceipt,
              replacement,
              'ledger.${replacement.kind.name}',
            )) {
          throw OperationConflict();
        }
        final edge = await db
            .customSelect(
              'SELECT original_id FROM event_reversals WHERE workspace=? AND event_id=?',
              variables: [
                Variable.withString(ws),
                Variable.withString(reversal.id.value),
              ],
            )
            .getSingleOrNull();
        if (edge?.read<String>('original_id') != original.id.value) {
          throw OperationConflict();
        }
      }
      final source = await readReversalSource(
        db,
        workspace,
        original.id,
        requireEligible: link == null,
      );
      final reversed = await _post(
        reversal,
        tags: source.tags,
        merchant: source.merchant,
        checkpoint: (point) => checkpoint?.call('reversal:$point'),
        correctionReceipt: (pair: correction, role: 'reversal'),
      );
      final replaced = await _post(
        replacement,
        tags: selections,
        merchant: replacementMerchant,
        checkpoint: (point) => checkpoint?.call('replacement:$point'),
        correctionReceipt: (pair: correction, role: 'replacement'),
      );
      if (link == null) {
        if (reversed.replayed || replaced.replayed) throw OperationConflict();
        await db.customStatement(
          'INSERT INTO event_corrections VALUES (?,?,?,?)',
          [ws, original.id.value, reversal.id.value, replacement.id.value],
        );
        checkpoint?.call('correction:link');
      } else if (!reversed.replayed || !replaced.replayed) {
        throw OperationConflict();
      }
      return CorrectionCommitResult(
        reversal.id,
        replacement.id,
        replayed: link != null,
      );
    });
  }

  /// Excludes an independent posted event from the effective ledger without
  /// deleting its historical rows or adding a second, reversing event.
  Future<CommitResult> tombstone(
    PostingTombstone command, {
    void Function(String)? checkpoint,
  }) async {
    if (!db.tombstonesAware) {
      throw UnsupportedError('Tombstones require schema 14.');
    }
    final original = command.original;
    final ws = command.operation.workspace.toString();
    final op = command.operation.operation.toString();
    final input = jsonEncode([
      'tombstone-v1',
      immutablePostingFacts(original),
      command.reason,
    ]);
    return db.transaction(() async {
      final marker = await db
          .customSelect(
            'SELECT operation_id,reason FROM event_tombstones WHERE workspace=? AND event_id=?',
            variables: [
              Variable.withString(ws),
              Variable.withString(original.id.value),
            ],
          )
          .getSingleOrNull();
      final receipt = await db
          .customSelect(
            'SELECT input,result_id FROM receipts WHERE workspace=? AND operation_id=?',
            variables: [Variable.withString(ws), Variable.withString(op)],
          )
          .getSingleOrNull();
      final audit = await db
          .customSelect(
            'SELECT entity_id,kind FROM audit WHERE workspace=? AND operation_id=?',
            variables: [Variable.withString(ws), Variable.withString(op)],
          )
          .getSingleOrNull();
      if (marker != null) {
        if (marker.read<String>('operation_id') != op ||
            marker.read<String>('reason') != command.reason ||
            receipt?.read<String>('input') != input ||
            receipt?.read<String>('result_id') != original.id.value ||
            audit?.read<String?>('entity_id') != original.id.value ||
            audit?.read<String>('kind') != 'ledger.tombstone') {
          throw OperationConflict();
        }
        return CommitResult(original.id, replayed: true);
      }
      if (receipt != null || audit != null) throw OperationConflict();
      return _commit(
        command.operation,
        input,
        original.id,
        () async {
          final source = await readReversalSource(
            db,
            command.operation.workspace,
            original.id,
          );
          if (jsonEncode(immutablePostingFacts(source.posting)) !=
              jsonEncode(immutablePostingFacts(original))) {
            throw const LedgerException(LedgerError.tombstoneReference);
          }
          await db.customStatement(
            'INSERT INTO event_tombstones VALUES (?,?,?,?)',
            [ws, original.id.value, op, command.reason],
          );
          checkpoint?.call('tombstone');
          await _checkBalances(original);
        },
        'ledger.tombstone',
        checkpoint,
      );
    });
  }

  Future<QueryRow?> _correctionReceipt(String ws, String operation) => db
      .customSelect(
        'SELECT r.result_id,a.entity_id,a.kind FROM receipts r LEFT JOIN audit a ON a.workspace=r.workspace AND a.operation_id=r.operation_id WHERE r.workspace=? AND r.operation_id=?',
        variables: [Variable.withString(ws), Variable.withString(operation)],
      )
      .getSingleOrNull();

  bool _matchingCorrectionReceipt(
    QueryRow? row,
    Posting posting,
    String kind,
  ) =>
      row != null &&
      row.read<String>('result_id') == posting.id.value &&
      row.read<String?>('entity_id') == posting.id.value &&
      row.read<String?>('kind') == kind;

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

  Future<int?> _validate(Posting posting, {int? refundSequence}) async {
    int? categorySequence = refundSequence;
    if (posting.refundOf == null &&
        posting.reversalOf == null &&
        posting.allocations.isNotEmpty) {
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
