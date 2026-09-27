import 'package:foundation_values/foundation_values.dart';

import 'posting.dart';

/// One financial correction proposal. Persistence must commit both postings
/// and their unique relationship in one transaction before either is visible.
final class PostingCorrection {
  PostingCorrection._(this.original, this.reversal, this.replacement);

  factory PostingCorrection({
    required Posting original,
    required Posting replacement,
    required PublicId reversalId,
    required OperationKey reversalOperation,
    String reason = '',
  }) {
    final supported =
        original.kind == PostingKind.income ||
        original.kind == PostingKind.expense ||
        original.kind == PostingKind.transfer;
    if (!supported ||
        replacement.kind != original.kind ||
        replacement.id == original.id ||
        replacement.id == reversalId ||
        reversalId == original.id ||
        replacement.operation == original.operation ||
        reversalOperation == original.operation ||
        replacement.operation == reversalOperation) {
      throw const LedgerException(LedgerError.correctionReference);
    }
    if (replacement.operation.workspace != original.operation.workspace ||
        reversalOperation.workspace != original.operation.workspace) {
      throw const LedgerException(LedgerError.workspaceMismatch);
    }
    final reversal = Posting.reversal(
      id: reversalId,
      operation: reversalOperation,
      date: original.date,
      original: original,
      reason: reason,
    );
    return PostingCorrection._(original, reversal, replacement);
  }

  final Posting original;
  final Posting reversal;
  final Posting replacement;
}
