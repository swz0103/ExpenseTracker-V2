import 'dart:convert';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

/// Partial text stays text: saving a draft never validates or posts money.
final class EntryFields {
  EntryFields({
    required this.income,
    required this.amount,
    required this.date,
    this.accountId,
    this.categoryId,
    this.merchantId,
    Iterable<PublicId> tags = const [],
  }) : tags = List.unmodifiable(tags) {
    if (amount.length > 128 ||
        date.length > 32 ||
        this.tags.length > 16 ||
        this.tags.toSet().length != this.tags.length) {
      throw const FormatException('Invalid draft fields');
    }
  }
  final bool income;
  final String amount, date;
  final PublicId? accountId, categoryId, merchantId;
  final List<PublicId> tags;
  List<Object?> toJson() => [
    income,
    amount,
    date,
    accountId?.value,
    categoryId?.value,
    merchantId?.value,
    [for (final t in tags) t.value],
  ];
  factory EntryFields.fromJson(Object? value) {
    final v = _list(value, 7);
    return EntryFields(
      income: v[0] as bool,
      amount: v[1] as String,
      date: v[2] as String,
      accountId: _id(v[3]),
      categoryId: _id(v[4]),
      merchantId: _id(v[5]),
      tags: (v[6] as List).map((e) => PublicId.parse(e as String)),
    );
  }
}

/// The frozen command survives commit-without-response and metadata changes.
final class EntrySubmission {
  EntrySubmission(
    this.posting, {
    Iterable<TagSelection> tags = const [],
    this.merchant,
  }) : tags = canonicalTags(tags) {
    if (![PostingKind.income, PostingKind.expense].contains(posting.kind) ||
        posting.legs.length != 1 ||
        posting.allocations.length > 1) {
      throw const FormatException('Unsupported draft submission');
    }
    if (posting.allocations.any((a) => a.expectedCategoryVersion == null)) {
      throw const FormatException('Missing category version');
    }
  }
  final Posting posting;
  final List<TagSelection> tags;
  final MerchantSelection? merchant;
  List<Object?> toJson() {
    final a = posting.legs.single.account;
    return [
      posting.kind.name,
      posting.date.toString(),
      [a.id.value, a.currency.code, a.currency.scale, a.expectedVersion],
      (posting.kind == PostingKind.income
              ? posting.reportIncome
              : posting.reportExpense)
          .minorUnits
          .toString(),
      [
        for (final c in posting.allocations)
          [c.categoryId.value, c.expectedCategoryVersion],
      ],
      [
        for (final t in tags) [t.id.value, t.expectedVersion],
      ],
      merchant == null ? null : [merchant!.id.value, merchant!.expectedVersion],
    ];
  }

  factory EntrySubmission.fromJson(
    Object? value,
    PublicId event,
    OperationKey operation,
  ) {
    final v = _list(value, 7);
    final a = _list(v[2], 4);
    final currency = Currency(a[1] as String, a[2] as int);
    final amount = Money(currency, BigInt.parse(v[3] as String));
    final kind = v[0];
    if (kind != 'income' && kind != 'expense') throw const FormatException();
    final factory = kind == 'income' ? Posting.income : Posting.expense;
    final posting = factory(
      id: event,
      operation: operation,
      date: BusinessDate.parse(v[1] as String),
      account: PostingAccount(
        id: PublicId.parse(a[0] as String),
        workspace: operation.workspace,
        currency: currency,
        expectedVersion: a[3] as int,
      ),
      amount: amount,
      allocations: (v[4] as List).map((e) {
        final c = _list(e, 2);
        return Allocation(
          PublicId.parse(c[0] as String),
          amount,
          expectedCategoryVersion: c[1] as int,
        );
      }).toList(),
    );
    final m = v[6] == null ? null : _list(v[6], 2);
    return EntrySubmission(
      posting,
      tags: (v[5] as List).map((e) {
        final t = _list(e, 2);
        return TagSelection(PublicId.parse(t[0] as String), t[1] as int);
      }),
      merchant: m == null
          ? null
          : MerchantSelection(PublicId.parse(m[0] as String), m[1] as int),
    );
  }
}

final class EntryDraft {
  EntryDraft({
    required this.id,
    required this.operation,
    required this.fields,
    this.submission,
  }) {
    if (submission != null &&
        (submission!.posting.id != id ||
            submission!.posting.operation.workspace != operation.workspace ||
            submission!.posting.operation.operation != operation.operation)) {
      throw const FormatException('Submission identity mismatch');
    }
  }
  final PublicId id;
  final OperationKey operation;
  final EntryFields fields;
  final EntrySubmission? submission;
  EntryDraft edit(EntryFields fields) {
    if (submission != null)
      throw StateError('Resolve pending submission first');
    return EntryDraft(id: id, operation: operation, fields: fields);
  }

  EntryDraft prepare(EntrySubmission command) => EntryDraft(
    id: id,
    operation: operation,
    fields: fields,
    submission: command,
  );
  String encode() => jsonEncode([
    'manual-entry-v1',
    id.value,
    operation.workspace.toString(),
    operation.operation.toString(),
    fields.toJson(),
    submission?.toJson(),
  ]);
  factory EntryDraft.decode(String text) {
    if (utf8.encode(text).length > 16384)
      throw const FormatException('Draft too large');
    final v = _list(jsonDecode(text), 6);
    if (v[0] != 'manual-entry-v1')
      throw const FormatException('Unknown draft version');
    final id = PublicId.parse(v[1] as String);
    final op = OperationKey(
      WorkspaceId.parse(v[2] as String),
      OperationId.parse(v[3] as String),
    );
    return EntryDraft(
      id: id,
      operation: op,
      fields: EntryFields.fromJson(v[4]),
      submission: v[5] == null ? null : EntrySubmission.fromJson(v[5], id, op),
    );
  }
}

List<dynamic> _list(Object? value, int length) {
  if (value is! List || value.length != length)
    throw const FormatException('Invalid draft shape');
  return value;
}

PublicId? _id(Object? value) =>
    value == null ? null : PublicId.parse(value as String);
