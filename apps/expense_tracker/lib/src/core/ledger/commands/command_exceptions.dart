/// What went wrong with a change of the ledger, for the screens to tell:
/// a change refused, or one the data source could not keep. Every case
/// the ledger can report is one of these, so a screen that tells them all
/// apart can be checked by the compiler.
sealed class LedgerProblem implements Exception {
  const LedgerProblem();
}

/// A change was refused because it would leave a later sale or reduction
/// of a stock short of shares.
final class SharesShort extends LedgerProblem {
  const SharesShort();

  @override
  String toString() => 'SharesShort';
}

/// A category was not added or renamed: its name is empty, taken, or one
/// the ledger keeps for itself.
final class NameTaken extends LedgerProblem {
  const NameTaken();

  @override
  String toString() => 'NameTaken';
}

/// A change made on screen could not be kept by the data source; the book
/// is read back as it was kept.
final class KeepFailed extends LedgerProblem {
  const KeepFailed(this.cause);

  /// What the data source threw.
  final Object cause;

  @override
  String toString() => 'KeepFailed($cause)';
}

/// After a change could not be kept, the book could not be read back
/// either; what the screens show may differ from what is kept.
final class ReloadFailed extends LedgerProblem {
  const ReloadFailed(this.cause);

  /// What the data source threw.
  final Object cause;

  @override
  String toString() => 'ReloadFailed($cause)';
}
