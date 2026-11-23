/// A change of the keys refused, with [message] to tell the person: the
/// current password wrong, or a new one against the password rule.
final class KeyRefused implements Exception {
  const KeyRefused(this.message);

  final String message;

  @override
  String toString() => 'KeyRefused';
}

/// The ledger's keys and backups, for the settings screen. Only the
/// encrypted ledger has one; the preview has none.
abstract interface class BackupManager {
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

  /// Saves [bytes] as a file named [name] outside the app, as
  /// [exportFile] does. False when the person cancels.
  Future<bool> exportBytes(String name, List<int> bytes);

  /// Lets the person choose a text file, such as a CSV to import, and
  /// returns its text; null when they cancel or there is no file picker.
  Future<String?> readFile();

  /// When a backup was last handed over by hand ([exportBackup]); null
  /// before the first.
  DateTime? get exportedAt;

  /// False for a ledger that opens without a password.
  bool get hasPassword;

  /// Whether the password last typed to open the ledger is shorter or
  /// simpler than one set today may be: it keeps working, and the
  /// settings suggest changing it.
  bool get passwordBelowRule;

  /// The password rule, said under the fields where one is set.
  String get passwordRule;

  /// Why [password] cannot be set as a password or backup passphrase, or
  /// null when it can: the vault's one rule.
  String? refusePassword(String password);

  /// Gives a ledger without a password the password [next]. Throws
  /// [KeyRefused] for one against the rule.
  Future<void> setPassword(String next);

  /// Replaces the password; [current] must open the ledger. Throws
  /// [KeyRefused] for a wrong [current] or a [next] against the rule.
  /// Backups already taken keep opening as they did.
  Future<void> changePassword(String current, String next);

  /// Replaces the recovery code and returns the new one, to show once.
  /// It opens the ledger and the backups from now on; backups already
  /// taken still open with the old one.
  Future<String> newRecoveryCode();

  /// Whether backups open with a backup passphrase as well as the
  /// recovery code.
  bool get hasBackupPassphrase;

  /// Sets the backup passphrase, held to the password policy.
  Future<void> setBackupPassphrase(String passphrase);

  /// Backups from now on open with the recovery code alone.
  Future<void> removeBackupPassphrase();

  /// Replaces every key of the ledger; [currentPassword] (null for a
  /// ledger without one) must open it. The app then opens the ledger
  /// afresh and shows the new recovery code.
  Future<void> resetKeys(String? currentPassword);

  /// Whether this phone can confirm a fingerprint or face, and the ledger
  /// has a password for it to stand in for.
  bool get canUseFingerprint;

  /// Whether the fingerprint opens the ledger.
  bool get fingerprintOn;

  /// Turns opening with the fingerprint [on] (the phone asks for it once)
  /// or off. False when the person turned the phone's prompt down:
  /// nothing changed and nothing is wrong.
  Future<bool> turnFingerprint({required bool on});

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
