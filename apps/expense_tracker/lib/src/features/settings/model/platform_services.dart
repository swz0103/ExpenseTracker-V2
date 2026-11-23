// Exception to models take what they use: it hands the preview a made-up
// ledger to open, so it names the type it makes (ADR-0013).

import 'package:flutter/foundation.dart';

import '../../../core/platform/sync_job.dart';
import 'app_update.dart';
import '../../backup/model/drive_sync.dart';
import '../../backup/model/backup_manager.dart';
import '../../backup/model/phone_backup.dart';
import '../../reminders/model/calendar_sync.dart';
import '../../entries/model/receipt_photos.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/navigation/nav.dart' show AppRoute;
import '../../reminders/model/reminder_alerts.dart';
import '../../../core/platform/preferences.dart';
import '../../../core/platform/quick_action.dart';
import '../../../core/platform/screen_privacy.dart';

/// What the phone and the open ledger offer the screens beyond the book:
/// keys and backups, the calendar for due dates, hiding the screens,
/// notifications, the person's preferences and the shortcuts that open
/// the composer. Each is absent in the preview but the preferences.
final class PlatformServices {
  const PlatformServices({
    this.backupManager,
    this.calendar,
    this.privacy,
    this.preferences,
    this.notifier,
    this.quick,
    this.sample,
    this.receipts,
    this.drive,
    this.phone,
    this.market,
    this.update,
    this.scanQr,
    this.onPlace,
    this.takeReturn,
    this.leave,
  });

  /// Told the page shown over the tabs each time it changes, so the lock
  /// gate knows where the person is.
  final ValueChanged<AppRoute?>? onPlace;

  /// The page to open on first, once: where the person was when they left
  /// for a restore they then gave up. Null otherwise.
  final AppRoute? Function()? takeReturn;

  /// Puts the app in the background without closing it, for back on the
  /// first screen; none where back closes the app (the preview).
  final Future<void> Function()? leave;

  final BackupManager? backupManager;
  final CalendarSync? calendar;
  final ScreenPrivacy? privacy;
  final Preferences? preferences;
  final Notifier? notifier;

  /// What a shortcut, the widget or a notification asked for, taken (set
  /// back to null) once acted on.
  final ValueNotifier<QuickAction?>? quick;

  /// The preview's made-up book, made afresh to start over from; none for
  /// a real ledger.
  final Ledger Function()? sample;

  /// The phone's receipt photos; none in the preview, which hides them.
  final ReceiptPhotos? receipts;

  /// Backups on Google Drive, on Android.
  final DriveSync? drive;

  /// Backups to a folder on the phone, on Android.
  final PhoneBackup? phone;

  /// Closing prices and rates; none in the preview.
  final SyncJob? market;

  /// Newer versions of the app, on Android.
  final AppUpdate? update;

  /// Reads a QR code, such as a paper e-invoice's, with the camera; none
  /// in the preview.
  final Future<String?> Function()? scanQr;
}
