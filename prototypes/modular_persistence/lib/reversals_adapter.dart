import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'adapters.dart';
import 'database.dart';

final class ReversalSourceRecord {
  const ReversalSourceRecord(
    this.posting,
    this.categorySequence,
    this.tags,
    this.tagSequence,
    this.merchant,
    this.merchantSequence,
  );
  final Posting posting;
  final int? categorySequence, tagSequence, merchantSequence;
  final List<TagSelection> tags;
  final MerchantSelection? merchant;
}

/// Only this read model refreshes account versions; immutable financial facts
/// and original metadata selections remain unchanged.
Future<ReversalSourceRecord> readReversalSource(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId originalId,
) async {
  if (!db.reversalsAware)
    throw UnsupportedError('Reversals require schema 11.');
  final args = [
    Variable.withString(workspace.toString()),
    Variable.withString(originalId.value),
  ];
  final e = await db
      .customSelect(
        'SELECT * FROM events WHERE workspace=? AND id=?',
        variables: args,
      )
      .getSingleOrNull();
  if (e == null ||
      !['income', 'expense', 'transfer'].contains(e.read<String>('kind'))) {
    throw const LedgerException(LedgerError.reversalReference);
  }
  for (final table in ['event_refunds', 'event_reversals']) {
    if ((await db
            .customSelect(
              'SELECT event_id FROM $table WHERE workspace=? AND original_id=? LIMIT 1',
              variables: args,
            )
            .get())
        .isNotEmpty) {
      throw const LedgerException(LedgerError.reversalDependency);
    }
  }
  final rows = await db
      .customSelect(
        'SELECT * FROM legs WHERE workspace=? AND event_id=? ORDER BY ordinal',
        variables: args,
      )
      .get();
  final accounts = <PostingAccount>[];
  for (final r in rows) {
    final a = await AccountsAdapter(db)
        .read(workspace, PublicId.parse(r.read<String>('account_id')));
    accounts.add(
      PostingAccount(
        id: a.id,
        workspace: workspace,
        currency: a.currency,
        expectedVersion: a.version,
      ),
    );
  }
  final allocationRows = await db
      .customSelect(
        'SELECT * FROM allocations WHERE workspace=? AND event_id=? ORDER BY category_id',
        variables: args,
      )
      .get();
  final c = Currency(e.read<String>('currency'), e.read<int>('scale'));
  final allocations = [
    for (final a in allocationRows)
      Allocation(
        PublicId.parse(a.read<String>('category_id')),
        Money(c, BigInt.from(a.read<int>('amount'))),
        expectedCategoryVersion: a.read<int>('category_version'),
      ),
  ];
  final receipt = await db
      .customSelect(
        "SELECT r.operation_id FROM receipts r JOIN audit a ON a.workspace=r.workspace AND a.operation_id=r.operation_id WHERE r.workspace=? AND r.result_id=? AND a.kind LIKE 'ledger.%'",
        variables: args,
      )
      .getSingle();
  final op = OperationKey(
    workspace,
    OperationId.parse(receipt.read<String>('operation_id')),
  );
  final date = BusinessDate.parse(e.read<String>('business_date'));
  final kind = e.read<String>('kind');
  final Posting original;
  if (kind == 'transfer') {
    original = Posting.transfer(
      id: originalId,
      operation: op,
      date: date,
      source: accounts[0],
      destination: accounts[1],
      principal: Money(c, -BigInt.from(rows[0].read<int>('amount'))),
      received: Money(
        accounts[1].currency,
        BigInt.from(rows[1].read<int>('amount')),
      ),
      fee: Money(c, BigInt.from(e.read<int>('expense'))),
    );
  } else {
    final create = kind == 'income' ? Posting.income : Posting.expense;
    original = create(
      id: originalId,
      operation: op,
      date: date,
      account: accounts.single,
      amount: Money(c, BigInt.from(e.read<int>(kind))),
      allocations: allocations,
    );
  }
  final tags = await db
      .customSelect(
        'SELECT * FROM event_tags WHERE workspace=? AND event_id=? ORDER BY tag_id',
        variables: args,
      )
      .get();
  final merchants = await db
      .customSelect(
        'SELECT * FROM event_merchants WHERE workspace=? AND event_id=?',
        variables: args,
      )
      .get();
  return ReversalSourceRecord(
    original,
    allocationRows.isEmpty
        ? null
        : allocationRows.first.read<int>('category_sequence'),
    List.unmodifiable([
      for (final t in tags)
        TagSelection(
          PublicId.parse(t.read<String>('tag_id')),
          t.read<int>('tag_version'),
        ),
    ]),
    tags.isEmpty ? null : tags.first.read<int>('tag_sequence'),
    merchants.isEmpty
        ? null
        : MerchantSelection(
            PublicId.parse(merchants.single.read<String>('merchant_id')),
            merchants.single.read<int>('merchant_version'),
          ),
    merchants.isEmpty ? null : merchants.single.read<int>('merchant_sequence'),
  );
}

Future<ReversalSourceRecord> validateReversalPosting(
  ProbeDatabase db,
  Posting posting,
  List<TagSelection> tags,
  MerchantSelection? merchant,
) async {
  final source = await readReversalSource(
    db,
    posting.operation.workspace,
    posting.reversalOf!,
  );
  // Version staleness is checked by Account.requirePosting below. Compare all
  // original financial facts independently of those refreshed account versions.
  Object facts(Posting p) => [
    p.id.value,
    p.operation.operation.toString(),
    p.kind.name,
    p.date.toString(),
    p.reportIncome.toJson(),
    p.reportExpense.toJson(),
    p.conversion?.toJson(),
    [
      for (final l in p.legs)
        [l.account.id.value, l.amount.toJson(), l.role.name],
    ],
    [
      for (final a
          in (p.allocations.toList()
            ..sort((a, b) => a.categoryId.value.compareTo(b.categoryId.value))))
        [a.categoryId.value, a.expectedCategoryVersion, a.amount.toJson()],
    ],
  ];
  if (jsonEncode(facts(source.posting)) !=
          jsonEncode(facts(posting.reversedPosting!)) ||
      jsonEncode([
            for (final t in source.tags) [t.id.value, t.expectedVersion],
          ]) !=
          jsonEncode([
            for (final t in tags) [t.id.value, t.expectedVersion],
          ]) ||
      source.merchant?.id != merchant?.id ||
      source.merchant?.expectedVersion != merchant?.expectedVersion) {
    throw const LedgerException(LedgerError.reversalReference);
  }
  return source;
}
