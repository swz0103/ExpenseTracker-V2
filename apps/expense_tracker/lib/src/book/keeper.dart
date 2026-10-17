/// The ledger's keys and backups, for the settings screen. Only the
/// encrypted ledger has one; the preview has none.
abstract interface class Keeper {
  /// Where backups are written.
  String get backupFolder;

  /// Writes an encrypted backup of the whole ledger and returns its path.
  Future<String> backUp();

  /// Writes a backup and lets the person keep a copy outside the app, such
  /// as in Downloads or on Google Drive. False when they cancel.
  Future<bool> exportBackup();

  /// Saves [text] as a file named [name] outside the app, as
  /// [exportBackup] does. False when the person cancels.
  Future<bool> exportFile(String name, String text);

  /// Replaces the password; [current] must open the ledger.
  Future<void> changePassword(String current, String next);

  /// Replaces the recovery code and returns the new one, to show once;
  /// the old one stops working.
  Future<String> newRecoveryCode();

  /// Closes the ledger once pending changes are kept, and returns to the
  /// lock screen.
  Future<void> lock();
}
