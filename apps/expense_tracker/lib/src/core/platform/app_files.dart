/// The names of the app's own files and folders, in its private files
/// directory and its cache: the one place they are written. The app
/// writes and reads them through these, `clearLeftovers` deletes the
/// plain copies by them, and the Android side, which needs some of them
/// before the app runs (the background backup, the widget, the photo and
/// file pickers), has the same names in `AppFiles.kt`; a test holds the
/// two together (test/core/platform/app_files_test.dart), and another
/// keeps these names out of every other Kotlin file
/// (test/rules/kotlin_literals_test.dart).
///
/// A name changed on one side only would leave a file behind, plaintext
/// among them, with nothing failing: hence one table.
abstract final class AppFiles {
  // ---- in the files directory ----

  /// The settings (`Preferences`): the choices, nothing that names the
  /// person.
  static const preferences = 'preferences.json';

  /// The settings that could name the person (the Google account, the
  /// backup folder, the budgets told of), sealed by the phone's Keystore.
  static const preferencesSealed = 'preferences.sealed';

  /// What the background jobs need of the settings, and no more
  /// (`Preferences.backgroundPlan`; BackupWorker.kt, UpdateWorker.kt).
  static const background = 'background.json';

  /// What the home-screen widget shows (`HomeWidget`).
  static const widget = 'widget.json';

  /// The sealed receipt photos.
  static const receipts = 'receipts';

  /// The encrypted backups the app keeps on the phone, one a week.
  static const backups = 'backups';

  /// Files waiting to be handed to another app (a backup, a CSV).
  static const exports = 'exports';

  /// What Android's own backup takes: [cloudCopy] and nothing else
  /// (res/xml/backup_rules.xml, data_extraction_rules.xml).
  static const cloud = 'cloud';

  /// The encrypted copy of the ledger in [cloud].
  static const cloudCopy = '記帳本.etbk';

  /// The backup waiting for the background job (`Outbox`), with
  /// [outboxReady] saying what it is and [outboxDelivered] what the job
  /// did with it.
  static const outbox = 'outbox';
  static const outboxReady = 'ready.json';
  static const outboxDelivered = 'delivered.json';

  // ---- in the cache ----

  /// A chosen backup copied in to be restored (`FilesHandler.kt`).
  static const restoreCopy = 'restore.etbk';

  /// A newer version handed to the installer.
  static const updates = 'updates';

  /// The camera's own photo before it is sealed (`PhotosHandler.kt`;
  /// res/xml/file_paths.xml shares this folder with the camera).
  static const camera = 'camera';

  /// The photo the camera writes into [camera].
  static const cameraPhoto = 'receipt.jpg';

  /// The photo made smaller, before the app seals it.
  static const receiptReady = 'receipt-ready.jpg';

  /// A photo taken while the phone closed the app, kept for a day.
  static const receiptLeftover = 'receipt-leftover.jpg';

  /// Every name above by the name `AppFiles.kt` gives it.
  static const all = <String, String>{
    'PREFERENCES': preferences,
    'PREFERENCES_SEALED': preferencesSealed,
    'BACKGROUND': background,
    'WIDGET': widget,
    'RECEIPTS': receipts,
    'BACKUPS': backups,
    'EXPORTS': exports,
    'CLOUD': cloud,
    'CLOUD_COPY': cloudCopy,
    'OUTBOX': outbox,
    'OUTBOX_READY': outboxReady,
    'OUTBOX_DELIVERED': outboxDelivered,
    'RESTORE_COPY': restoreCopy,
    'UPDATES': updates,
    'CAMERA': camera,
    'CAMERA_PHOTO': cameraPhoto,
    'RECEIPT_READY': receiptReady,
    'RECEIPT_LEFTOVER': receiptLeftover,
  };
}
