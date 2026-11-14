/// The ledger's keys and backups, for the settings screen. Only the
/// encrypted ledger has one; the preview has none.
abstract interface class Keeper {
  /// Writes a backup and lets the person keep a copy outside the app, such
  /// as in Downloads or on Google Drive. False when they cancel.
  Future<bool> exportBackup();

  /// Saves [text] as a file named [name] outside the app, as
  /// [exportBackup] does. False when the person cancels.
  Future<bool> exportFile(String name, String text);

  /// When the copy Android's own backup takes to the person's Google
  /// account was last written; null before the first.
  DateTime? get cloudCopyAt;

  /// When Android last took that copy to the person's Google account
  /// (LedgerBackupAgent.kt writes it down); null before the first. Android
  /// does it about once a day, while the phone charges on Wi-Fi, and only
  /// with backup turned on in the phone's settings.
  DateTime? get googleTakenAt;

  /// Deletes the copy Android's own backup takes, when Google 備份 is
  /// turned off: Android then backs up nothing of the ledger.
  Future<void> dropCloudCopy();

  /// Saves [bytes] as a file named [name] outside the app, as
  /// [exportFile] does. False when the person cancels.
  Future<bool> exportBytes(String name, List<int> bytes);

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
