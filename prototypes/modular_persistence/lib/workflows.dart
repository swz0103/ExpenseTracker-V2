import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'adapters.dart';
import 'database.dart';

final class OperationConflict implements Exception {}

final class CommitResult {
  const CommitResult(this.id, {required this.replayed});
  final PublicId id;
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
    void Function(String)? checkpoint,
  }) => _commit(
    posting.operation,
    jsonEncode(postingInput(posting)),
    posting.id,
    () async {
      await _validate(posting);
      await ledger.insert(posting, checkpoint: checkpoint);
      await _checkBalances(posting);
    },
    'ledger.${posting.kind.name}',
    checkpoint,
  );

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

  Future<void> _validate(Posting posting) async {
    // Categories are not integrated yet: reject rather than accept unverified IDs.
    if (posting.allocations.isNotEmpty)
      throw UnsupportedError(
        'Category references require the Categories adapter.',
      );
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
  }

  Future<CommitResult> _commit(
    OperationKey operation,
    String input,
    PublicId proposedId,
    Future<void> Function() write,
    String kind,
    void Function(String)? checkpoint,
  ) => db.transaction(() async {
    final ws = operation.workspace.toString();
    final op = operation.operation.toString();
    final existing = await db
        .customSelect(
          'SELECT input,result_id FROM receipts WHERE workspace = ? AND operation_id = ?',
          variables: [Variable.withString(ws), Variable.withString(op)],
        )
        .get();
    if (existing.isNotEmpty) {
      if (existing.single.read<String>('input') != input)
        throw OperationConflict();
      return CommitResult(
        PublicId.parse(existing.single.read<String>('result_id')),
        replayed: true,
      );
    }
    await write();
    await db.customStatement('INSERT INTO receipts VALUES (?,?,?,?)', [
      ws,
      op,
      input,
      proposedId.value,
    ]);
    checkpoint?.call('receipt');
    await db.customStatement('INSERT INTO audit VALUES (?,?,?,?,?)', [
      ws,
      op,
      proposedId.value,
      kind,
      UtcInstant(DateTime.now()).toString(),
    ]);
    checkpoint?.call('audit');
    return CommitResult(proposedId, replayed: false);
  });
}
