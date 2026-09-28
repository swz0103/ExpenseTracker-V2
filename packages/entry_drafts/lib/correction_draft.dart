part of 'entry_drafts.dart';

List<Object?> _correctionFields(EntryFields fields) {
  final replacement = EntryFields(
    income: fields.income,
    transfer: fields.transfer,
    split: fields.split,
    amount: fields.amount,
    date: fields.date,
    accountId: fields.accountId,
    destinationId: fields.destinationId,
    fee: fields.fee,
    received: fields.received,
    categoryId: fields.categoryId,
    merchantId: fields.merchantId,
    splits: fields.splits,
    tags: fields.tags,
  );
  return [
    fields.correctionOf!.value,
    fields.correctionReason,
    fields.income,
    fields.transfer,
    fields.split,
    fields.received != null,
    replacement.toJson(),
  ];
}

EntryFields _readCorrectionFields(Object? value) {
  final v = _list(value, 7);
  final replacement = EntryFields.fromJson(
    v[6],
    transfer: v[3] as bool,
    crossCurrency: v[5] as bool,
    split: v[4] as bool,
  );
  if (replacement.income != v[2]) throw const FormatException();
  return EntryFields(
    income: replacement.income,
    transfer: replacement.transfer,
    split: replacement.split,
    amount: replacement.amount,
    date: replacement.date,
    accountId: replacement.accountId,
    destinationId: replacement.destinationId,
    fee: replacement.fee,
    received: replacement.received,
    categoryId: replacement.categoryId,
    merchantId: replacement.merchantId,
    splits: replacement.splits,
    tags: replacement.tags,
    correctionOf: PublicId.parse(v[0] as String),
    correctionReason: v[1] as String,
  );
}

/// Frozen pair: a restart can prove both events and the correction link before
/// deleting the local encrypted draft. The original is an immutable fact.
final class CorrectionSubmission {
  CorrectionSubmission(
    this.pair, {
    Iterable<TagSelection> tags = const [],
    this.merchant,
  }) : tags = canonicalTags(tags) {
    EntrySubmission(pair.original);
    EntrySubmission(pair.replacement, tags: this.tags, merchant: merchant);
  }

  final PostingCorrection pair;
  final List<TagSelection> tags;
  final MerchantSelection? merchant;

  List<Object?> toJson() {
    final original = pair.original, replacement = pair.replacement;
    return [
      'correction-v1',
      original.id.value,
      original.operation.operation.toString(),
      original.kind == PostingKind.transfer,
      original.conversion != null,
      original.allocations.length > 1,
      EntrySubmission(original).toJson(split: original.allocations.length > 1),
      pair.reversal.id.value,
      pair.reversal.operation.operation.toString(),
      pair.reversal.reversalReason,
      replacement.kind == PostingKind.transfer,
      replacement.conversion != null,
      replacement.allocations.length > 1,
      EntrySubmission(
        replacement,
        tags: tags,
        merchant: merchant,
      ).toJson(split: replacement.allocations.length > 1),
    ];
  }

  factory CorrectionSubmission.fromJson(
    Object? value,
    PublicId replacementId,
    OperationKey replacementOperation,
  ) {
    final v = _list(value, 14);
    if (v[0] != 'correction-v1') throw const FormatException();
    final workspace = replacementOperation.workspace;
    final original = EntrySubmission.fromJson(
      v[6],
      PublicId.parse(v[1] as String),
      OperationKey(workspace, OperationId.parse(v[2] as String)),
      transfer: v[3] as bool,
      crossCurrency: v[4] as bool,
      split: v[5] as bool,
    );
    final replacement = EntrySubmission.fromJson(
      v[13],
      replacementId,
      replacementOperation,
      transfer: v[10] as bool,
      crossCurrency: v[11] as bool,
      split: v[12] as bool,
    );
    return CorrectionSubmission(
      PostingCorrection(
        original: original.posting,
        replacement: replacement.posting,
        reversalId: PublicId.parse(v[7] as String),
        reversalOperation: OperationKey(
          workspace,
          OperationId.parse(v[8] as String),
        ),
        reason: v[9] as String,
      ),
      tags: replacement.tags,
      merchant: replacement.merchant,
    );
  }
}
