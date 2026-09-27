import 'package:drift/drift.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'database.dart';

final class RefundSourceRecord {
  const RefundSourceRecord(
    this.accountId,
    this.originalAmount,
    this.budget,
    this.categorySequence,
    this.tags,
    this.tagSequence,
    this.merchant,
    this.merchantSequence,
  );
  final PublicId accountId;
  final Money originalAmount;
  final RefundBudget budget;
  final int? categorySequence, tagSequence, merchantSequence;
  final List<TagSelection> tags;
  final MerchantSelection? merchant;
}

Future<RefundSourceRecord> readRefundSource(
  ProbeDatabase db,
  WorkspaceId workspace,
  PublicId originalId,
) async {
  if (!db.refundsAware) throw UnsupportedError('Refunds require schema 10.');
  final args = [
    Variable.withString(workspace.toString()),
    Variable.withString(originalId.value),
  ];
  final event = await db
      .customSelect(
        "SELECT e.*,l.account_id FROM events e JOIN legs l ON l.workspace=e.workspace AND l.event_id=e.id AND l.ordinal=0 WHERE e.workspace=? AND e.id=?",
        variables: args,
      )
      .getSingleOrNull();
  if (event == null || event.read<String>('kind') != 'expense') {
    throw const LedgerException(LedgerError.refundReference);
  }
  final currency = Currency(
    event.read<String>('currency'),
    event.read<int>('scale'),
  );
  final amount = Money(currency, BigInt.from(event.read<int>('expense')));
  final sourceAllocations = await db
      .customSelect(
        'SELECT * FROM allocations WHERE workspace=? AND event_id=? ORDER BY category_id',
        variables: args,
      )
      .get();
  Allocation allocation(QueryRow row) => Allocation(
    PublicId.parse(row.read<String>('category_id')),
    Money(currency, BigInt.from(row.read<int>('amount'))),
    expectedCategoryVersion: row.read<int>('category_version'),
  );
  var budget = RefundBudget(
    originalId: originalId,
    originalDate: BusinessDate.parse(event.read<String>('business_date')),
    amount: amount,
    allocations: sourceAllocations.map(allocation).toList(),
  );

  // All accepted refunds are positive and cumulatively bounded by one original
  // Money value, so these integer sums cannot overflow a valid ledger. SQLite
  // rejects corrupt overflows; never cast sums to REAL or silently round.
  final totals = await db
      .customSelect(
        'SELECT COALESCE(SUM(-e.expense),0) AS refunded,MIN(-e.expense) AS minimum,MIN(e.business_date) AS first_date '
        'FROM event_refunds r JOIN events e ON e.workspace=r.workspace AND e.id=r.event_id '
        'WHERE r.workspace=? AND r.original_id=?',
        variables: args,
      )
      .getSingle();
  final minimum = totals.readNullable<int>('minimum');
  if (minimum != null) {
    if (minimum <= 0) throw const LedgerException(LedgerError.refundReference);
    final attributed = await db
        .customSelect(
          'SELECT a.category_id,a.category_version,SUM(a.amount) AS amount,MIN(a.amount) AS minimum '
          'FROM event_refunds r JOIN allocations a ON a.workspace=r.workspace AND a.event_id=r.event_id '
          'WHERE r.workspace=? AND r.original_id=? GROUP BY a.category_id,a.category_version',
          variables: args,
        )
        .get();
    if (attributed.any((r) => r.read<int>('minimum') <= 0)) {
      throw const LedgerException(LedgerError.refundReference);
    }
    budget = budget.consume(
      amount: Money(currency, BigInt.from(totals.read<int>('refunded'))),
      date: BusinessDate.parse(totals.read<String>('first_date')),
      allocations: attributed.map(allocation).toList(),
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
  return RefundSourceRecord(
    PublicId.parse(event.read<String>('account_id')),
    amount,
    budget,
    sourceAllocations.isEmpty
        ? null
        : sourceAllocations.first.read<int>('category_sequence'),
    List.unmodifiable(
      tags.map(
        (r) => TagSelection(
          PublicId.parse(r.read<String>('tag_id')),
          r.read<int>('tag_version'),
        ),
      ),
    ),
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

/// Runs inside the same transaction as the new event and operation receipt.
/// An original category/tag/merchant can be archived now: its historical
/// selection is retained, while receiving Account rules still apply today.
Future<RefundSourceRecord> validateRefundPosting(
  ProbeDatabase db,
  Posting posting,
  List<TagSelection> tags,
  MerchantSelection? merchant,
) async {
  final source = await readRefundSource(
    db,
    posting.operation.workspace,
    posting.refundOf!,
  );
  source.budget.consume(
    amount: -posting.reportExpense,
    date: posting.date,
    allocations: posting.allocations,
  );
  if (source.tags.length != tags.length ||
      List.generate(
        tags.length,
        (i) =>
            tags[i].id == source.tags[i].id &&
            tags[i].expectedVersion == source.tags[i].expectedVersion,
      ).contains(false) ||
      source.merchant?.id != merchant?.id ||
      source.merchant?.expectedVersion != merchant?.expectedVersion) {
    throw const LedgerException(LedgerError.refundReference);
  }
  return source;
}
