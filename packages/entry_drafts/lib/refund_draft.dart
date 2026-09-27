part of 'entry_drafts.dart';

EntryFields _refundFields(Object? value) {
  final v = _list(value, 6);
  return EntryFields(
    income: false,
    refundOf: PublicId.parse(v[0] as String),
    amount: v[1] as String,
    date: v[2] as String,
    accountId: _id(v[3]),
    received: v[4] as String?,
    splits: (v[5] as List).map((e) {
      final r = _list(e, 2);
      return SplitFields(categoryId: _id(r[0]), amount: r[1] as String);
    }),
  );
}

List<Object?> _refundSubmission(EntrySubmission command) {
  final p = command.posting, a = p.legs.single.account;
  return [
    'refund',
    p.refundOf!.value,
    p.date.toString(),
    [a.id.value, a.currency.code, a.currency.scale, a.expectedVersion],
    (-p.reportExpense).toJson(),
    p.legs.single.amount.minorUnits.toString(),
    [
      for (final c in p.allocations)
        [
          c.categoryId.value,
          c.expectedCategoryVersion,
          c.amount.minorUnits.toString(),
        ],
    ],
    [
      for (final t in command.tags) [t.id.value, t.expectedVersion],
    ],
    command.merchant == null
        ? null
        : [command.merchant!.id.value, command.merchant!.expectedVersion],
  ];
}

EntrySubmission _readRefundSubmission(
  Object? value,
  PublicId event,
  OperationKey operation,
) {
  final v = _list(value, 9);
  if (v[0] != 'refund') throw const FormatException();
  final a = _list(v[3], 4), currency = Currency(a[1] as String, a[2] as int);
  final amount = Money.fromJson((v[4] as Map).cast<String, Object?>());
  final merchant = v[8] == null ? null : _list(v[8], 2);
  return EntrySubmission(
    Posting.refund(
      id: event,
      operation: operation,
      date: BusinessDate.parse(v[2] as String),
      originalId: PublicId.parse(v[1] as String),
      account: PostingAccount(
        id: PublicId.parse(a[0] as String),
        workspace: operation.workspace,
        currency: currency,
        expectedVersion: a[3] as int,
      ),
      amount: amount,
      received: Money(currency, BigInt.parse(v[5] as String)),
      allocations: (v[6] as List).map((e) {
        final row = _list(e, 3);
        return Allocation(
          PublicId.parse(row[0] as String),
          Money(amount.currency, BigInt.parse(row[2] as String)),
          expectedCategoryVersion: row[1] as int,
        );
      }).toList(),
    ),
    tags: (v[7] as List).map((e) {
      final row = _list(e, 2);
      return TagSelection(PublicId.parse(row[0] as String), row[1] as int);
    }),
    merchant: merchant == null
        ? null
        : MerchantSelection(
            PublicId.parse(merchant[0] as String),
            merchant[1] as int,
          ),
  );
}
