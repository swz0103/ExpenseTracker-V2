import 'package:foundation_values/foundation_values.dart';

import 'posting.dart';

/// Immutable deletion request. It has no effect until persistence atomically
/// validates the frozen source and records its unique tombstone and receipt.
final class PostingTombstone {
  PostingTombstone({
    required this.original,
    required this.operation,
    this.reason = '',
  }) {
    if (![
          PostingKind.income,
          PostingKind.expense,
          PostingKind.transfer,
        ].contains(original.kind) ||
        operation.operation == original.operation.operation ||
        reason != reason.trim() ||
        reason.runes.length > 256) {
      throw const LedgerException(LedgerError.tombstoneReference);
    }
    if (operation.workspace != original.operation.workspace) {
      throw const LedgerException(LedgerError.workspaceMismatch);
    }
  }

  final Posting original;
  final OperationKey operation;
  final String reason;
}
