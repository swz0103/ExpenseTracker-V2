part of 'entry_drafts.dart';

/// Frozen deletion source and operation survive commit-without-response.
final class TombstoneSubmission {
  TombstoneSubmission(this.command) {
    EntrySubmission(command.original);
  }
  final PostingTombstone command;

  List<Object?> toJson() {
    final original = command.original;
    return [
      'tombstone-v1',
      original.operation.operation.toString(),
      original.kind == PostingKind.transfer,
      original.conversion != null,
      original.allocations.length > 1,
      EntrySubmission(original).toJson(split: original.allocations.length > 1),
      command.reason,
    ];
  }

  factory TombstoneSubmission.fromJson(
    Object? value,
    PublicId originalId,
    OperationKey operation,
  ) {
    final v = _list(value, 7);
    if (v[0] != 'tombstone-v1') throw const FormatException();
    final source = EntrySubmission.fromJson(
      v[5],
      originalId,
      OperationKey(operation.workspace, OperationId.parse(v[1] as String)),
      transfer: v[2] as bool,
      crossCurrency: v[3] as bool,
      split: v[4] as bool,
    );
    return TombstoneSubmission(
      PostingTombstone(
        original: source.posting,
        operation: operation,
        reason: v[6] as String,
      ),
    );
  }
}
