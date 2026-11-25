/// Why a backup could not be read or restored. Never carries key material
/// or ledger content.
enum BackupProblem {
  /// Not a backup file, or a truncated or reordered one.
  invalidFormat,

  /// Written by a newer app.
  unsupportedVersion,

  /// The keys do not open this backup, or its content was altered.
  authenticationFailed,

  /// The target ledger already has data.
  targetNotEmpty,

  /// The content decrypted but is not a ledger the app can read.
  invalidContent,

  /// Larger than any backup is ([LedgerBackup.maxBackupBytes]): refused
  /// before it is read, and never written.
  tooLarge,
}

final class BackupException implements Exception {
  const BackupException(this.problem, [this.detail = '']);

  final BackupProblem problem;

  /// A non-secret hint for diagnostics, such as a record's shelf.
  final String detail;

  @override
  String toString() => 'BackupException(${problem.name} $detail)';
}

enum VaultProblem {
  /// [LedgerVault.create] found a ledger already on this device.
  alreadyExists,

  /// No ledger on this device yet.
  missing,

  /// The keyring file cannot be read.
  damagedKeyring,

  /// A keyring for another ledger was offered.
  otherLedger,

  /// A restored database failed its checks; nothing was kept.
  damagedRestore,

  /// The keyring is here but the ledger's database is gone: opening would
  /// start an empty ledger as if nothing had been kept, so it is refused.
  missingDatabase,
}

final class VaultException implements Exception {
  const VaultException(this.problem);

  final VaultProblem problem;

  @override
  String toString() => 'VaultException(${problem.name})';
}
