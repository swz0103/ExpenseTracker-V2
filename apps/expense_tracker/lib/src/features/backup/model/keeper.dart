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

  /// Lets the person choose a text file, such as a CSV to import, and
  /// returns its text; null when they cancel or there is no file picker.
  Future<String?> readFile();

  /// False for a ledger that opens without a password.
  bool get hasPassword;

  /// Gives a ledger without a password the password [next].
  Future<void> setPassword(String next);

  /// Replaces the password; [current] must open the ledger.
  Future<void> changePassword(String current, String next);

  /// Replaces the recovery code and returns the new one, to show once;
  /// the old one stops working.
  Future<String> newRecoveryCode();

  /// Whether a recovery code has been shown on this phone, so exporting
  /// a backup need not replace it.
  bool get recoveryGiven;

  /// Closes the ledger once pending changes are kept, and returns to the
  /// lock screen.
  Future<void> lock();
}
