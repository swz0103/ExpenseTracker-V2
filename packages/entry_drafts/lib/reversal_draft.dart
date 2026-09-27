part of 'entry_drafts.dart';

List<Object?> _reversalSubmission(EntrySubmission command) {
  final p = command.posting, original = p.reversedPosting!;
  final source = EntrySubmission(
    original,
    tags: command.tags,
    merchant: command.merchant,
  );
  return [
    'reversal',
    p.date.toString(),
    p.reversalReason,
    original.id.value,
    original.operation.operation.toString(),
    original.kind == PostingKind.transfer,
    original.conversion != null,
    original.allocations.length > 1,
    source.toJson(split: original.allocations.length > 1),
  ];
}

EntrySubmission _readReversalSubmission(
  Object? value,
  PublicId event,
  OperationKey operation,
) {
  final v = _list(value, 9);
  if (v[0] != 'reversal') throw const FormatException();
  final source = EntrySubmission.fromJson(
    v[8],
    PublicId.parse(v[3] as String),
    OperationKey(operation.workspace, OperationId.parse(v[4] as String)),
    transfer: v[5] as bool,
    crossCurrency: v[6] as bool,
    split: v[7] as bool,
  );
  return EntrySubmission(
    Posting.reversal(
      id: event,
      operation: operation,
      date: BusinessDate.parse(v[1] as String),
      reason: v[2] as String,
      original: source.posting,
    ),
    tags: source.tags,
    merchant: source.merchant,
  );
}
