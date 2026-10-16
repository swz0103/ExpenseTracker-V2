/// The ledger's keys and backups, for the settings screen. Only the
/// encrypted ledger has one; the preview has none.
abstract interface class Keeper {
  /// Where backups are written.
  String get backupFolder;

  /// Writes an encrypted backup of the whole ledger and returns its path.
  Future<String> backUp();

  /// Replaces the password; [current] must open the ledger.
  Future<void> changePassword(String current, String next);

  /// Replaces the recovery code and returns the new one, to show once;
  /// the old one stops working.
  Future<String> newRecoveryCode();

  /// Closes the ledger and returns to the lock screen.
  void lock();
}
