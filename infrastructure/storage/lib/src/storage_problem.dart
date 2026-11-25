/// Why a store could not be opened. Never carries key material.
enum StorageProblem {
  /// The SQLite library is not SQLCipher; the file would be plaintext.
  notEncrypted,

  /// The key does not open this file.
  wrongKey,

  /// The file was written by a newer build than this one.
  newerSchema,

  /// The file is a ledger of the event-journal format, from before
  /// records were kept as rows; this build cannot read it.
  oldFormat,

  /// Another connection, isolate or process already has the file open;
  /// only one may own a ledger at a time.
  inUse,

  /// The file is not a whole ledger: empty, cut short, or a page of it
  /// damaged (decision D94). Told apart from [wrongKey] as far as the file
  /// and the key's origin allow ([EncryptedDatabase.open]); never thrown
  /// over by writing a new, empty ledger in its place.
  damaged,
}

final class StorageUnavailable implements Exception {
  const StorageUnavailable(this.problem);

  final StorageProblem problem;

  @override
  bool operator ==(Object other) =>
      other is StorageUnavailable && other.problem == problem;

  @override
  int get hashCode => problem.hashCode;

  @override
  String toString() => 'StorageUnavailable(${problem.name})';
}
