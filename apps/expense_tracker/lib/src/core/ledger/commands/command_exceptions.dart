/// A change was refused because it would leave a later sale or reduction
/// of a stock short of shares.
final class SharesShort implements Exception {
  const SharesShort();

  @override
  String toString() => 'SharesShort';
}

/// A category was not added or renamed: its name is empty, taken, or one
/// the ledger keeps for itself.
final class NameTaken implements Exception {
  const NameTaken();

  @override
  String toString() => 'NameTaken';
}
