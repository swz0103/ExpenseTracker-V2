/// What opening a backup through found: when it was taken, its records
/// and receipt photos.
typedef BackupCheck = ({DateTime at, int rows, int photos});

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

  /// Opens the newest backup kept on this phone the way a restore does,
  /// into a scratch copy that is thrown away, so a damaged backup is
  /// found before it is needed; one is written first when there is none.
  /// Throws when it does not open.
  Future<BackupCheck> checkNewest();

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

  /// Keeps a backup of this ledger with its photos in the app's backup
  /// folder, then closes it and opens the lock screen on restoring
  /// another backup in its place. Returns where the backup was kept.
  Future<String> restoreAnother();
}
